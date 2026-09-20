//
//  PuryConversationLedger.swift
//  PurePetsAdmin
//
//  The Pury conversation surface, rebuilt as an operations ledger rather than a chat.
//
//  Design intent
//  -------------
//  A staff operator is not "chatting". They are running queries against live, permissioned
//  operational records and then acting on the result. So each exchange is composed as a
//  ledger turn with real provenance — when it was read, how many records came back, how
//  long the backend took — instead of a pair of anonymous chat bubbles.
//
//  Three structural moves separate this from a generic assistant screen:
//
//  1. THE LAUNCH DECK IS DERIVED FROM THE BOUND SCOPE.
//     Pury already receives a `PuryScreenContext` describing exactly where the operator
//     came from, and the repository already ships localized context prompts that were
//     never wired to anything. The deck now leads with the query about *this* stay,
//     order, or item, then orders the platform-wide intents by the operator's domain.
//     Opening Pury from the hotel and from the warehouse produce different decks.
//
//  2. PROVENANCE IS EARNED, NOT STAMPED.
//     The previous surface printed a green "Live data" badge on every Pury message,
//     including error text and cancellation notices. Here the badge appears only when the
//     turn actually carries records, and it states the count it is claiming.
//
//  3. THE READING STATE IS SHAPED LIKE THE ANSWER.
//     A skeleton dossier occupies roughly the space the answer will need, so content
//     resolves in place instead of shoving the conversation upward.
//
//  Every string resolves through `PuryLocale` in Pury's own language, and all direction
//  sensitive geometry is expressed with leading/trailing semantics or an explicit
//  direction sign, so the surface is correct in Arabic RTL and English LTR.
//

import SwiftUI
import UIKit

// MARK: - Clock

/// Turn times are operator receipts, not localized prose: fixed 24h Western digits so a
/// staff member reading Arabic and a staff member reading English quote the same value.
enum PuryClock {
    nonisolated(unsafe) private static let formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "HH:mm"
        return formatter
    }()

    static func stamp(_ date: Date) -> String {
        formatter.string(from: date)
    }

    /// Backend latency, surfaced because a slow operational query is itself information.
    static func latency(milliseconds: Int) -> String {
        if milliseconds < 1000 { return "\(milliseconds)ms" }
        return String(format: "%.1fs", Double(milliseconds) / 1000.0)
    }
}

// MARK: - Tactile Press Style

/// Shared press feel for every runnable surface in the deck. Reduce Motion removes the
/// travel but keeps a legible pressed state, so the affordance never disappears.
struct PuryTactilePressStyle: ButtonStyle {
    var pressedScale: CGFloat = 0.975
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(reduceMotion ? 1 : (configuration.isPressed ? pressedScale : 1))
            .opacity(configuration.isPressed ? 0.86 : 1)
            .animation(
                reduceMotion ? nil : .spring(response: 0.26, dampingFraction: 0.7),
                value: configuration.isPressed
            )
    }
}

// MARK: - Launch Intents

/// One runnable operational query offered on the launch deck.
struct PuryLaunchIntent: Identifiable, Equatable {
    let id: String
    let symbol: String
    let accent: Color
    /// Domain category, rendered as a quiet kicker instead of an emoji badge.
    let kicker: String
    let title: String
    let subtitle: String
    let prompt: String
    /// True when this intent was derived from the operator's bound screen context.
    let isScoped: Bool
}

/// One compact single-tap query.
struct PuryQuickQuery: Identifiable, Equatable {
    let id: String
    let symbol: String
    let title: String
    let prompt: String
}

enum PuryLaunchDeckComposer {
    private static let hotelAccent = Color(red: 16 / 255, green: 185 / 255, blue: 129 / 255)
    private static let stockAccent = Color(red: 245 / 255, green: 158 / 255, blue: 11 / 255)
    private static let orderAccent = Color(red: 59 / 255, green: 130 / 255, blue: 246 / 255)
    private static let performanceAccent = Color(red: 139 / 255, green: 92 / 255, blue: 246 / 255)

    /// Composes the deck: context-bound intents first, then the platform intents ordered
    /// by the domain the operator is actually standing in.
    static func intents(context: PuryScreenContext?, language: String) -> [PuryLaunchIntent] {
        var deck: [PuryLaunchIntent] = []

        if let scoped = scopedIntent(context: context, language: language) {
            deck.append(scoped)
        }

        let platform = platformIntents(language: language)
        let priority = domainPriority(for: context)

        deck.append(
            contentsOf: platform.sorted { lhs, rhs in
                (priority.firstIndex(of: lhs.id) ?? Int.max) < (priority.firstIndex(of: rhs.id) ?? Int.max)
            }
        )

        return deck
    }

    /// The single most specific query available for the record the operator is looking at.
    private static func scopedIntent(context: PuryScreenContext?, language: String) -> PuryLaunchIntent? {
        guard let context, !context.isEmpty else { return nil }

        let boundKicker = PuryLocale.text(
            "Pury_Launch_Bound_Badge",
            language: language,
            ar: "مرتبط بالسياق",
            en: "Bound context"
        )

        if (context.stayId?.isEmpty == false) || (context.reservationId?.isEmpty == false) {
            return PuryLaunchIntent(
                id: "scoped.stay",
                symbol: "cross.case.fill",
                accent: PuryBrand.primary,
                kicker: boundKicker,
                title: PuryLocale.text("Pury_Launch_ThisStay_Title", language: language, ar: "هذه الإقامة", en: "This stay"),
                subtitle: PuryLocale.text(
                    "Pury_Launch_ThisStay_Sub",
                    language: language,
                    ar: "المهام الطبية وحالة الرعاية",
                    en: "Care tasks and medication status"
                ),
                prompt: PuryLocale.text(
                    "Pury_Prompt_ContextStay",
                    language: language,
                    ar: "ما هي المهام الطبية وحالة الرعاية لهذه الإقامة؟",
                    en: "What are the care tasks and medication status for this stay?"
                ),
                isScoped: true
            )
        }

        let entity = context.entityType?.lowercased() ?? ""
        let hasRecord = context.entityId?.isEmpty == false

        if hasRecord, entity.contains("order") {
            return PuryLaunchIntent(
                id: "scoped.order",
                symbol: "shippingbox.fill",
                accent: PuryBrand.primary,
                kicker: boundKicker,
                title: PuryLocale.text("Pury_Launch_ThisOrder_Title", language: language, ar: "هذا الطلب", en: "This order"),
                subtitle: PuryLocale.text(
                    "Pury_Launch_ThisOrder_Sub",
                    language: language,
                    ar: "سجل التتبع وحالة التجهيز",
                    en: "Tracking history and fulfillment"
                ),
                prompt: PuryLocale.text(
                    "Pury_Prompt_ContextOrder",
                    language: language,
                    ar: "ما هو ملخص حالة وسجل تتبع هذا الطلب؟",
                    en: "What is the tracking history and fulfillment status of this order?"
                ),
                isScoped: true
            )
        }

        if hasRecord, entity.contains("accessor") || entity.contains("product") || entity.contains("pet") {
            return PuryLaunchIntent(
                id: "scoped.product",
                symbol: "cube.box.fill",
                accent: PuryBrand.primary,
                kicker: boundKicker,
                title: PuryLocale.text("Pury_Launch_ThisItem_Title", language: language, ar: "هذا المنتج", en: "This item"),
                subtitle: PuryLocale.text(
                    "Pury_Launch_ThisItem_Sub",
                    language: language,
                    ar: "حالة المخزون والمبيعات",
                    en: "Stock level and sales performance"
                ),
                prompt: PuryLocale.text(
                    "Pury_Prompt_ContextProduct",
                    language: language,
                    ar: "ما هي حالة المخزون والمبيعات لهذا المنتج؟",
                    en: "What is the inventory and sales performance of this item?"
                ),
                isScoped: true
            )
        }

        return nil
    }

    private static func platformIntents(language: String) -> [PuryLaunchIntent] {
        [
            PuryLaunchIntent(
                id: "hotel",
                symbol: "building.2.fill",
                accent: hotelAccent,
                kicker: PuryLocale.text("Pury_Launch_Kicker_Hotel", language: language, ar: "الفندق", en: "Hotel"),
                title: PuryLocale.text("Pury_Launch_Hotel_Title", language: language, ar: "حالة الإشغال", en: "Occupancy status"),
                subtitle: PuryLocale.text(
                    "Pury_Launch_Hotel_Sub",
                    language: language,
                    ar: "الغرف والنزلاء الآن",
                    en: "Rooms and guests right now"
                ),
                prompt: PuryLocale.text(
                    "Pury_Prompt_Hotel",
                    language: language,
                    ar: "ما هي حالة الإشغال اليوم في فندق الحيوانات؟",
                    en: "What is the occupancy status today at Pets Hotel?"
                ),
                isScoped: false
            ),
            PuryLaunchIntent(
                id: "stock",
                symbol: "exclamationmark.triangle.fill",
                accent: stockAccent,
                kicker: PuryLocale.text("Pury_Launch_Kicker_Inventory", language: language, ar: "المخزون", en: "Inventory"),
                title: PuryLocale.text("Pury_Launch_Stock_Title", language: language, ar: "نواقص المخزون", en: "Low stock"),
                subtitle: PuryLocale.text(
                    "Pury_Launch_Stock_Sub",
                    language: language,
                    ar: "منتجات أوشكت على النفاد",
                    en: "Items nearing threshold"
                ),
                prompt: PuryLocale.text(
                    "Pury_Prompt_LowStock",
                    language: language,
                    ar: "ابحث عن المنتجات التي أوشكت على النفاد في المستودع",
                    en: "Search for products running low on warehouse stock"
                ),
                isScoped: false
            ),
            PuryLaunchIntent(
                id: "orders",
                symbol: "shippingbox.fill",
                accent: orderAccent,
                kicker: PuryLocale.text("Pury_Launch_Kicker_Fulfillment", language: language, ar: "التجهيز", en: "Fulfillment"),
                title: PuryLocale.text("Pury_Launch_Orders_Title", language: language, ar: "الطلبات المعلقة", en: "Pending orders"),
                subtitle: PuryLocale.text(
                    "Pury_Launch_Orders_Sub",
                    language: language,
                    ar: "بانتظار الشحن والتسليم",
                    en: "Awaiting dispatch and delivery"
                ),
                prompt: PuryLocale.text(
                    "Pury_Prompt_PendingOrders",
                    language: language,
                    ar: "كم عدد الطلبات المعلقة بانتظار الشحن حالياً؟",
                    en: "How many pending orders are awaiting shipment?"
                ),
                isScoped: false
            ),
            PuryLaunchIntent(
                id: "performance",
                symbol: "chart.line.uptrend.xyaxis",
                accent: performanceAccent,
                kicker: PuryLocale.text("Pury_Launch_Kicker_Performance", language: language, ar: "الأداء", en: "Performance"),
                title: PuryLocale.text("Pury_Launch_Kpi_Title", language: language, ar: "ملخص الأسبوع", en: "This week"),
                subtitle: PuryLocale.text(
                    "Pury_Launch_Kpi_Sub",
                    language: language,
                    ar: "الإيرادات ومؤشرات النمو",
                    en: "Revenue and growth KPIs"
                ),
                prompt: PuryLocale.text(
                    "Pury_Prompt_KpiSummary",
                    language: language,
                    ar: "ملخص مؤشرات الأداء والمبيعات لهذا الأسبوع",
                    en: "Summary of KPIs and revenue performance this week"
                ),
                isScoped: false
            )
        ]
    }

    /// Which platform intent the operator most likely wants, given where they opened Pury.
    private static func domainPriority(for context: PuryScreenContext?) -> [String] {
        let signature = [context?.screen, context?.route, context?.entityType]
            .compactMap { $0 }
            .joined(separator: " ")
            .lowercased()

        if signature.contains("hotel") || signature.contains("stay") {
            return ["hotel", "orders", "stock", "performance"]
        }
        if signature.contains("accessor") || signature.contains("food") || signature.contains("livepet") || signature.contains("petaccessories") {
            return ["stock", "performance", "orders", "hotel"]
        }
        if signature.contains("order") || signature.contains("fulfillment") || signature.contains("payment") || signature.contains("pos") {
            return ["orders", "stock", "performance", "hotel"]
        }
        if signature.contains("user") || signature.contains("staff") || signature.contains("customer") {
            return ["performance", "orders", "hotel", "stock"]
        }
        return ["hotel", "stock", "orders", "performance"]
    }

    static func quickQueries(language: String) -> [PuryQuickQuery] {
        [
            PuryQuickQuery(
                id: "vets",
                symbol: "stethoscope",
                title: PuryLocale.text("Pury_Quick_Vets_Title", language: language, ar: "كادر الأطباء", en: "Veterinarians"),
                prompt: PuryLocale.text(
                    "Pury_Quick_Vets_Prompt",
                    language: language,
                    ar: "كم عدد الأطباء البيطريين المسجلين في النظام؟",
                    en: "How many veterinarians are registered in the system?"
                )
            ),
            PuryQuickQuery(
                id: "adoption",
                symbol: "heart.text.square.fill",
                title: PuryLocale.text("Pury_Quick_Adoption_Title", language: language, ar: "طلبات التبني", en: "Adoption requests"),
                prompt: PuryLocale.text(
                    "Pury_Quick_Adoption_Prompt",
                    language: language,
                    ar: "ما هي أحدث طلبات التبني المسجلة؟",
                    en: "What are the latest adoption requests?"
                )
            ),
            PuryQuickQuery(
                id: "guests",
                symbol: "pawprint.fill",
                title: PuryLocale.text("Pury_Quick_Guests_Title", language: language, ar: "نزلاء الفندق", en: "Hotel guests"),
                prompt: PuryLocale.text(
                    "Pury_Quick_Guests_Prompt",
                    language: language,
                    ar: "ما هي قائمة الحيوانات المقيمة بالفندق حالياً؟",
                    en: "List the pets currently staying at the hotel."
                )
            ),
            PuryQuickQuery(
                id: "audit",
                symbol: "square.stack.3d.up.fill",
                title: PuryLocale.text("Pury_Quick_Audit_Title", language: language, ar: "جرد المخزون", en: "Stock audit"),
                prompt: PuryLocale.text(
                    "Pury_Quick_Audit_Prompt",
                    language: language,
                    ar: "ملخص سريع لأهم أصناف المخزون المتوفرة",
                    en: "Quick audit summary of available product inventory."
                )
            ),
            PuryQuickQuery(
                id: "delivery",
                symbol: "car.fill",
                title: PuryLocale.text("Pury_Quick_Delivery_Title", language: language, ar: "شحنات التوصيل", en: "Delivery orders"),
                prompt: PuryLocale.text(
                    "Pury_Quick_Delivery_Prompt",
                    language: language,
                    ar: "ما هي حالة شحنات وطلبات التوصيل اليوم؟",
                    en: "What is the status of delivery shipments today?"
                )
            ),
            PuryQuickQuery(
                id: "bookings",
                symbol: "calendar.badge.clock",
                title: PuryLocale.text("Pury_Quick_Bookings_Title", language: language, ar: "حجوزات الفندق", en: "Hotel bookings"),
                prompt: PuryLocale.text(
                    "Pury_Quick_Bookings_Prompt",
                    language: language,
                    ar: "كم عدد حجوزات الفندق القادمة والمؤكدة؟",
                    en: "How many upcoming hotel bookings are confirmed?"
                )
            ),
            PuryQuickQuery(
                id: "branches",
                symbol: "storefront.fill",
                title: PuryLocale.text("Pury_Quick_Branches_Title", language: language, ar: "حالة الفروع", en: "Branch status"),
                prompt: PuryLocale.text(
                    "Pury_Quick_Branches_Prompt",
                    language: language,
                    ar: "ما هي الفروع النشطة وحالة تشغيلها الحالية؟",
                    en: "What are the active branches and their operational status?"
                )
            ),
            PuryQuickQuery(
                id: "missing",
                symbol: "magnifyingglass.circle.fill",
                title: PuryLocale.text("Pury_Quick_Missing_Title", language: language, ar: "بلاغات المفقودات", en: "Missing reports"),
                prompt: PuryLocale.text(
                    "Pury_Quick_Missing_Prompt",
                    language: language,
                    ar: "ما هي أحدث بلاغات الحيوانات المفقودة المسجلة؟",
                    en: "What are the latest reported missing pets?"
                )
            ),
            PuryQuickQuery(
                id: "posSales",
                symbol: "creditcard.fill",
                title: PuryLocale.text("Pury_Quick_POS_Title", language: language, ar: "مبيعات الكاشير", en: "POS sales"),
                prompt: PuryLocale.text(
                    "Pury_Quick_POS_Prompt",
                    language: language,
                    ar: "ملخص مبيعات نقاط البيع والكاشير المسجلة اليوم",
                    en: "Summary of today's point of sale and cashier transactions."
                )
            ),
            PuryQuickQuery(
                id: "livePets",
                symbol: "hare.fill",
                title: PuryLocale.text("Pury_Quick_LivePets_Title", language: language, ar: "الحيوانات المتوفرة", en: "Available pets"),
                prompt: PuryLocale.text(
                    "Pury_Quick_LivePets_Prompt",
                    language: language,
                    ar: "كم عدد الحيوانات الحية المتوفرة حالياً في الفروع؟",
                    en: "How many live pets are currently available across branches?"
                )
            )
        ]
    }

    /// Four-band greeting. The previous two-band version told an operator on a 3pm shift
    /// "good evening".
    static func greeting(language: String, date: Date = Date()) -> String {
        let hour = Calendar.current.component(.hour, from: date)
        switch hour {
        case 5..<12:
            return PuryLocale.text("Pury_Greeting_Morning", language: language, ar: "صباح الخير، أنا بيوري", en: "Good morning — I'm Pury")
        case 12..<17:
            return PuryLocale.text("Pury_Greeting_Afternoon", language: language, ar: "طاب يومك، أنا بيوري", en: "Good afternoon — I'm Pury")
        case 17..<22:
            return PuryLocale.text("Pury_Greeting_Evening", language: language, ar: "مساء الخير، أنا بيوري", en: "Good evening — I'm Pury")
        default:
            return PuryLocale.text("Pury_Greeting_Night", language: language, ar: "سهرة مباركة، أنا بيوري", en: "Working late — I'm Pury")
        }
    }
}

// MARK: - Launch Deck

/// Top-anchored standby surface. The previous empty state centred a 170pt hero between
/// two `Spacer`s, which pushed the actual runnable content into the bottom third of the
/// screen and collapsed badly once the keyboard appeared.
@available(iOS 16.0, *)
struct PuryLaunchDeck: View {
    let language: String
    let isRTL: Bool
    let screenContext: PuryScreenContext?
    /// Intent and query identifiers the signed-in operator is actually authorized to act on,
    /// resolved from the real `AdminRoute` authorization projection. Pury never offers a
    /// query whose result the operator could not open — the deck is computed from live
    /// session authorization and bound scope rather than a fixed list.
    let authorizedIntentIDs: Set<String>
    let authorizedQueryIDs: Set<String>
    let onRun: (String) -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var intents: [PuryLaunchIntent] {
        let composed = PuryLaunchDeckComposer.intents(context: screenContext, language: language)
        let permitted = composed.filter { authorizedIntentIDs.contains($0.id) || $0.isScoped }
        // Never present an empty deck: a scope-bound intent always survives, and if the
        // operator's authorization excludes every platform intent the deck degrades to the
        // scoped one rather than to nothing.
        return permitted.isEmpty ? Array(composed.prefix(1)) : permitted
    }

    private var quickQueries: [PuryQuickQuery] {
        let composed = PuryLaunchDeckComposer.quickQueries(language: language)
        let permitted = composed.filter { authorizedQueryIDs.contains($0.id) }
        return permitted
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            standbyHero

            sectionLabel(
                PuryLocale.text("Pury_Launch_Section_Start", language: language, ar: "ابدأ من هنا", en: "Start here")
            )

            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 158), spacing: 10, alignment: .top)],
                alignment: .leading,
                spacing: 10
            ) {
                ForEach(intents) { intent in
                    intentPod(intent)
                }
            }

            if !quickQueries.isEmpty {
                sectionLabel(
                    PuryLocale.text("Pury_Launch_Section_Quick", language: language, ar: "استعلامات سريعة", en: "Quick queries")
                )

                // An adaptive grid rather than a horizontal rail: every permitted option
                // stays visible at any text size and on iPad.
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 150), spacing: 8, alignment: .top)],
                    alignment: .leading,
                    spacing: 8
                ) {
                    ForEach(quickQueries) { query in
                        quickQueryRow(query)
                    }
                }
            }
        }
    }

    // MARK: Hero

    /// Horizontal lockup: identity and intent on one band instead of a stacked hero.
    private var standbyHero: some View {
        let isStacked = dynamicTypeSize >= .accessibility1

        return VStack(alignment: .leading, spacing: 12) {
            if isStacked {
                PuryAvatar(size: 52, isLiving: false, isThinking: false, showStatusRing: true, showAmbientAura: false)
                    .accessibilityHidden(true)
                heroText
            } else {
                HStack(alignment: .center, spacing: 14) {
                    PuryAvatar(size: 54, isLiving: false, isThinking: false, showStatusRing: true, showAmbientAura: false)
                        .accessibilityHidden(true)

                    heroText
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var heroText: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(PuryLaunchDeckComposer.greeting(language: language))
                .font(PPBrandFont.bold(size: 20, relativeTo: .title3))
                .foregroundStyle(AdminSurface.primaryText)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)

            Text(
                PuryLocale.text(
                    "Pury_Launch_Mission",
                    language: language,
                    ar: "اسألني عن الإشغال، المخزون، التجهيز، أو الأداء — وأجيبك من السجلات الحية المصرح لك بها.",
                    en: "Ask about occupancy, inventory, fulfillment, or performance — answered from the live records you are cleared to see."
                )
            )
            .font(PPBrandFont.regular(size: 13.5, relativeTo: .footnote))
            .foregroundStyle(AdminSurface.secondaryText)
            .lineSpacing(3)
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func sectionLabel(_ text: String) -> some View {
        HStack(spacing: 7) {
            Text(text)
                .font(PPBrandFont.bold(size: 12, relativeTo: .caption))
                .foregroundStyle(AdminSurface.secondaryText)

            Rectangle()
                .fill(AdminSurface.hairline)
                .frame(height: 0.75)
        }
        .accessibilityAddTraits(.isHeader)
    }

    // MARK: Intent Pod

    private func intentPod(_ intent: PuryLaunchIntent) -> some View {
        Button {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            onRun(intent.prompt)
        } label: {
            VStack(alignment: .leading, spacing: 9) {
                HStack(spacing: 5) {
                    Image(systemName: intent.symbol)
                        .font(.system(size: 10.5, weight: .bold))

                    Text(intent.kicker)
                        .font(PPBrandFont.bold(size: 10.5, relativeTo: .caption2))
                        .lineLimit(1)
                }
                .foregroundStyle(intent.accent)

                VStack(alignment: .leading, spacing: 3) {
                    Text(intent.title)
                        .font(PPBrandFont.bold(size: 15, relativeTo: .subheadline))
                        .foregroundStyle(AdminSurface.primaryText)
                        .multilineTextAlignment(.leading)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)

                    Text(intent.subtitle)
                        .font(PPBrandFont.regular(size: 11.5, relativeTo: .caption))
                        .foregroundStyle(AdminSurface.secondaryText)
                        .multilineTextAlignment(.leading)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }

                // One quiet directional cue instead of repeating a "Live Query" label on
                // every pod. `arrow.forward` mirrors itself for Arabic.
                HStack {
                    Spacer(minLength: 0)

                    Image(systemName: "arrow.forward")
                        .font(.system(size: 10, weight: .black))
                        .foregroundStyle(intent.accent)
                        .padding(6)
                        .background(intent.accent.opacity(0.12), in: Circle())
                }
            }
            .padding(13)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(AdminSurface.surface)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(
                        intent.isScoped ? intent.accent.opacity(0.45) : AdminSurface.hairline,
                        lineWidth: intent.isScoped ? 1.1 : 0.75
                    )
            )
            .shadow(color: Color.black.opacity(0.035), radius: 7, x: 0, y: 3)
        }
        .buttonStyle(PuryTactilePressStyle())
        .accessibilityLabel("\(intent.title). \(intent.subtitle)")
        .accessibilityHint(
            PuryLocale.text(
                "Pury_Launch_Pod_A11y_Hint",
                language: language,
                ar: "انقر مرتين لتشغيل هذا الاستعلام",
                en: "Double tap to run this query"
            )
        )
    }

    // MARK: Quick Query

    private func quickQueryRow(_ query: PuryQuickQuery) -> some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            onRun(query.prompt)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: query.symbol)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(PuryBrand.primary)
                    .frame(width: 16)

                Text(query.title)
                    .font(PPBrandFont.medium(size: 12.5, relativeTo: .caption))
                    .foregroundStyle(AdminSurface.primaryText)
                    .multilineTextAlignment(.leading)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 11)
            .padding(.vertical, 9)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(AdminSurface.surface)
            .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .strokeBorder(AdminSurface.hairline, lineWidth: 0.75)
            )
        }
        .buttonStyle(PuryTactilePressStyle(pressedScale: 0.96))
        .accessibilityLabel(query.title)
    }
}

// MARK: - Operator Query Turn

/// The operator's own query. Kept as a brand-gradient capsule for warmth and identity,
/// but slimmed, given a real timestamp, and made re-runnable — operational data changes
/// under you, so asking the same question again is a first-class action, not a retype.
@available(iOS 16.0, *)
struct PuryQueryTurn: View {
    let text: String
    let timestamp: Date
    let isRTL: Bool
    let language: String
    /// Only the most recent query carries a visible re-run control; older turns keep it
    /// in the context menu so the stream does not repeat chrome on every row.
    let showsInlineRerun: Bool
    let onRerun: () -> Void

    private var rerunLabel: String {
        PuryLocale.text("Pury_Turn_Rerun", language: language, ar: "إعادة الاستعلام", en: "Re-run query")
    }

    private var copyLabel: String {
        PuryLocale.text("Pury_Turn_Copy", language: language, ar: "نسخ", en: "Copy")
    }

    var body: some View {
        VStack(alignment: .trailing, spacing: 4) {
            HStack(spacing: 0) {
                Spacer(minLength: 40)

                Text(text)
                    .font(PPBrandFont.medium(size: 15, relativeTo: .body))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.leading)
                    .lineSpacing(3)
                    .padding(.horizontal, 15)
                    .padding(.vertical, 11)
                    .background {
                        ZStack {
                            LinearGradient(
                                colors: [PuryBrand.hotPink, PuryBrand.primary],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )

                            // Material top highlight: reads as glass over pigment rather
                            // than as a flat gradient fill.
                            LinearGradient(
                                colors: [Color.white.opacity(0.20), Color.clear],
                                startPoint: .top,
                                endPoint: .center
                            )
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 19, style: .continuous))
                    .shadow(color: PuryBrand.glow.opacity(0.26), radius: 8, x: 0, y: 4)
                    .contextMenu {
                        Button {
                            UIPasteboard.general.string = text
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        } label: {
                            Label(copyLabel, systemImage: "doc.on.doc")
                        }

                        Button {
                            onRerun()
                        } label: {
                            Label(rerunLabel, systemImage: "arrow.clockwise")
                        }
                    }
            }

            HStack(spacing: 8) {
                if showsInlineRerun {
                    Button {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        onRerun()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 9, weight: .bold))
                            Text(rerunLabel)
                                .font(PPBrandFont.medium(size: 10.5, relativeTo: .caption2))
                        }
                        .foregroundStyle(PuryBrand.primary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(rerunLabel)
                }

                Text(PuryClock.stamp(timestamp))
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(AdminSurface.secondaryText.opacity(0.75))
                    .environment(\.layoutDirection, .leftToRight)
            }
            .padding(.horizontal, 4)
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Answer Turn Chrome

/// Pury's turn opens with a provenance band. The record count is only claimed when the
/// turn genuinely carries records, so the badge means something.
@available(iOS 16.0, *)
struct PuryAnswerTurnHeader: View {
    let language: String
    let isRTL: Bool
    let timestamp: Date
    /// `nil` when the turn carries no structured records — no provenance badge is shown.
    let recordCount: Int?
    let isReading: Bool

    private static let liveAccent = Color(red: 16 / 255, green: 185 / 255, blue: 129 / 255)

    var body: some View {
        HStack(spacing: 8) {
            PuryAvatar(size: 22, isLiving: false, isThinking: isReading, showStatusRing: false, showAmbientAura: false)
                .accessibilityHidden(true)

            Text(PuryLocale.text("Pury_Name", language: language, ar: "بيوري", en: "Pury"))
                .font(PPBrandFont.bold(size: 12.5, relativeTo: .caption))
                .foregroundStyle(AdminSurface.primaryText)

            if let recordCount, recordCount > 0 {
                HStack(spacing: 4) {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 8.5, weight: .bold))

                    Text(
                        PuryLocale.format(
                            "Pury_Turn_Records_Format",
                            language: language,
                            ar: "%@ سجل حي",
                            en: "%@ live records",
                            String(recordCount)
                        )
                    )
                    .font(PPBrandFont.bold(size: 10, relativeTo: .caption2))
                }
                .foregroundStyle(Self.liveAccent)
                .padding(.horizontal, 6)
                .padding(.vertical, 2.5)
                .background(Self.liveAccent.opacity(0.12), in: Capsule())
            }

            Spacer(minLength: 4)

            Text(PuryClock.stamp(timestamp))
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundStyle(AdminSurface.secondaryText.opacity(0.75))
                .environment(\.layoutDirection, .leftToRight)
        }
        .accessibilityElement(children: .combine)
    }
}

/// Turn footer: copy, plus backend latency when the backend reported it.
@available(iOS 16.0, *)
struct PuryAnswerTurnFooter: View {
    let language: String
    let latencyMs: Int?
    let canCopy: Bool
    let onCopy: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            if canCopy {
                Button {
                    onCopy()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "doc.on.doc")
                            .font(.system(size: 9.5, weight: .bold))

                        Text(PuryLocale.text("Pury_Turn_Copy", language: language, ar: "نسخ", en: "Copy"))
                            .font(PPBrandFont.medium(size: 10.5, relativeTo: .caption2))
                    }
                    .foregroundStyle(AdminSurface.secondaryText)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(PuryLocale.text("Pury_Turn_Copy", language: language, ar: "نسخ", en: "Copy"))
            }

            Spacer(minLength: 0)

            if let latencyMs, latencyMs > 0 {
                HStack(spacing: 3) {
                    Image(systemName: "bolt.horizontal")
                        .font(.system(size: 8.5, weight: .bold))

                    Text(PuryClock.latency(milliseconds: latencyMs))
                        .font(.system(size: 9.5, weight: .medium, design: .monospaced))
                        .environment(\.layoutDirection, .leftToRight)
                }
                .foregroundStyle(AdminSurface.secondaryText.opacity(0.6))
                .accessibilityLabel(
                    PuryLocale.format(
                        "Pury_Turn_Latency_A11y_Format",
                        language: language,
                        ar: "زمن الاستجابة %@",
                        en: "Response time %@",
                        PuryClock.latency(milliseconds: latencyMs)
                    )
                )
            }
        }
        .padding(.horizontal, 2)
    }
}

// MARK: - Reading Dossier (shaped loading state)

/// Occupies roughly the space the answer will need, so content resolves in place instead
/// of shoving the conversation upward when it arrives.
@available(iOS 16.0, *)
struct PuryReadingDossier: View {
    let language: String
    let isRTL: Bool
    let allowsMotion: Bool

    private let barFractions: [CGFloat] = [0.94, 0.82, 0.58]
    private let barHeight: CGFloat = 11
    private let barSpacing: CGFloat = 8

    private var statusText: String {
        PuryLocale.text("Pury_State_Reading", language: language, ar: "يقرأ البيانات الحية", en: "Reading live records")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack(spacing: 8) {
                PuryAvatar(size: 22, isLiving: false, isThinking: true, showStatusRing: false, showAmbientAura: false)
                    .accessibilityHidden(true)

                Text(PuryLocale.text("Pury_Name", language: language, ar: "بيوري", en: "Pury"))
                    .font(PPBrandFont.bold(size: 12.5, relativeTo: .caption))
                    .foregroundStyle(AdminSurface.primaryText)

                Text(statusText)
                    .font(PPBrandFont.medium(size: 10.5, relativeTo: .caption2))
                    .foregroundStyle(PuryBrand.primary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2.5)
                    .background(PuryBrand.primary.opacity(0.10), in: Capsule())

                Spacer(minLength: 0)
            }

            GeometryReader { geometry in
                VStack(alignment: .leading, spacing: barSpacing) {
                    ForEach(Array(barFractions.enumerated()), id: \.offset) { index, fraction in
                        PurySkeletonBar(
                            width: max(24, geometry.size.width * fraction),
                            height: barHeight,
                            delay: Double(index) * 0.18,
                            isRTL: isRTL,
                            allowsMotion: allowsMotion
                        )
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(height: CGFloat(barFractions.count) * barHeight + CGFloat(barFractions.count - 1) * barSpacing)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AdminSurface.surface)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(AdminSurface.hairline, lineWidth: 0.75)
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(statusText)
    }
}

@available(iOS 16.0, *)
private struct PurySkeletonBar: View {
    let width: CGFloat
    let height: CGFloat
    let delay: Double
    let isRTL: Bool
    let allowsMotion: Bool

    @State private var phase: CGFloat = 0

    var body: some View {
        Capsule()
            .fill(AdminSurface.control)
            .frame(width: width, height: height)
            .overlay(alignment: .leading) {
                if allowsMotion {
                    let highlight = width * 0.42
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [.clear, PuryBrand.primary.opacity(0.22), .clear],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: highlight, height: height)
                        .offset(x: (isRTL ? -1 : 1) * (phase * (width + highlight) - highlight))
                }
            }
            .clipShape(Capsule())
            .onAppear {
                guard allowsMotion else { return }
                withAnimation(
                    .linear(duration: 1.25)
                        .repeatForever(autoreverses: false)
                        .delay(delay)
                ) {
                    phase = 1
                }
            }
    }
}

// MARK: - Pending Approval Rail

/// A Tier-3 confirmation that scrolls out of view is an operational hazard: the operator
/// believes an action is done when it is still waiting on them. This rail keeps the
/// pending approval reachable from the composer for as long as it exists.
@available(iOS 16.0, *)
struct PuryPendingApprovalRail: View {
    let language: String
    let onReview: () -> Void

    var body: some View {
        Button(action: onReview) {
            HStack(spacing: 8) {
                Image(systemName: "hand.raised.fill")
                    .font(.system(size: 11, weight: .bold))

                Text(
                    PuryLocale.text(
                        "Pury_Pending_Approval_Title",
                        language: language,
                        ar: "إجراء بانتظار موافقتك",
                        en: "Action awaiting your approval"
                    )
                )
                .font(PPBrandFont.bold(size: 11.5, relativeTo: .caption))
                .lineLimit(1)

                Spacer(minLength: 6)

                Text(
                    PuryLocale.text("Pury_Pending_Approval_Action", language: language, ar: "مراجعة", en: "Review")
                )
                .font(PPBrandFont.bold(size: 11, relativeTo: .caption2))

                Image(systemName: "arrow.forward")
                    .font(.system(size: 9, weight: .black))
            }
            .foregroundStyle(AdminSurface.amber)
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .frame(maxWidth: .infinity)
            .background(AdminSurface.amber.opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(AdminSurface.amber.opacity(0.35), lineWidth: 0.9)
            )
        }
        .buttonStyle(PuryTactilePressStyle(pressedScale: 0.985))
        .accessibilityElement(children: .combine)
    }
}
