//
//  ProformaInvoicesView.swift
//  PurePetsAdmin
//
//  Category-Defining Proforma Invoices & Commercial Quotes Studio
//  Reengineered to follow the NextGen POS Sales Journal UI pattern:
//  - Atmospheric Branch Sales Journal layout with prominent period statement & disclosure facts
//  - Living Transaction Dossier Card with quick actions (WhatsApp, Call, PDF Share, Fast Copy)
//  - Full-screen dual-architecture Dossier (iPhone Cockpit + iPad Dual-Wing Console)
//  - Dedicated Proforma Studio Editor with tactile line items, catalog drawer & live estimates
//  - Tactile Commercial Conversion Studio following POS Refund & Void Sheet paradigms
//  Strictly enforces Beiruti brand typography, Arabic RTL excellence, and 6-state resilience.
//

import SwiftUI
import UIKit

// MARK: - Brand Typography (100% Beiruti Invariant)

enum PFType {
    static let largeTitle = Font.custom("Beiruti-Bold", size: 38, relativeTo: .largeTitle)
    static let title = Font.custom("Beiruti-Bold", size: 32, relativeTo: .title)
    static let title2 = Font.custom("Beiruti-Bold", size: 24, relativeTo: .title2)
    static let title3 = Font.custom("Beiruti-Bold", size: 20, relativeTo: .title3)
    static let headline = Font.custom("Beiruti-Bold", size: 17, relativeTo: .headline)
    static let subheadline = Font.custom("Beiruti-Regular", size: 15, relativeTo: .subheadline)
    static let subheadlineBold = Font.custom("Beiruti-Bold", size: 15, relativeTo: .subheadline)
    static let body = Font.custom("Beiruti-Regular", size: 17, relativeTo: .body)
    static let bodyBold = Font.custom("Beiruti-Bold", size: 17, relativeTo: .body)
    static let callout = Font.custom("Beiruti-Regular", size: 16, relativeTo: .callout)
    static let calloutBold = Font.custom("Beiruti-Medium", size: 16, relativeTo: .callout)
    static let footnote = Font.custom("Beiruti-Regular", size: 14, relativeTo: .footnote)
    static let footnoteBold = Font.custom("Beiruti-Bold", size: 14, relativeTo: .footnote)
    static let caption = Font.custom("Beiruti-Regular", size: 12, relativeTo: .caption)
    static let captionBold = Font.custom("Beiruti-Medium", size: 13, relativeTo: .caption)
    static let caption2 = Font.custom("Beiruti-Regular", size: 11, relativeTo: .caption2)
    static let caption2Bold = Font.custom("Beiruti-Bold", size: 11, relativeTo: .caption2)

    static func bold(size: CGFloat) -> Font { Font.custom("Beiruti-Bold", size: size) }
    static func medium(size: CGFloat) -> Font { Font.custom("Beiruti-Medium", size: size) }
    static func regular(size: CGFloat) -> Font { Font.custom("Beiruti-Regular", size: size) }
}

private enum DossierFont {
    static func bold(_ size: CGFloat, relativeTo textStyle: Font.TextStyle = .body) -> Font {
        Font.custom("Beiruti-Bold", size: size, relativeTo: textStyle)
    }
    static func medium(_ size: CGFloat, relativeTo textStyle: Font.TextStyle = .body) -> Font {
        Font.custom("Beiruti-Medium", size: size, relativeTo: textStyle)
    }
    static func regular(_ size: CGFloat, relativeTo textStyle: Font.TextStyle = .body) -> Font {
        Font.custom("Beiruti-Regular", size: size, relativeTo: textStyle)
    }
}

// MARK: - Journal Primitives & Button Styles

private struct POSJournalButtonStyle: ButtonStyle {
    var filled = false
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(filled ? Color.white : AdminSurface.primary)
            .background(
                filled
                    ? (configuration.isPressed ? AdminSurface.primaryPressed : AdminSurface.primary)
                    : (configuration.isPressed ? AdminSurface.backgroundSecondary : Color.clear),
                in: RoundedRectangle(cornerRadius: 12, style: .continuous)
            )
            .opacity(isEnabled ? 1 : 0.5)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

private struct POSReceiptActionStyle: ButtonStyle {
    var surface: Color = AdminSurface.backgroundSecondary
    var cornerRadius: CGFloat = 10
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(isEnabled ? AdminSurface.primaryText : AdminSurface.secondaryText)
            .background(
                configuration.isPressed ? AdminSurface.hairline : surface,
                in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            )
            .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

/// Amounts stay in their own directional island; surrounding content keeps language direction.
private struct POSJournalAmount: View {
    let value: Double
    let currency: String
    var prominent = false
    var amountFont: Font? = nil

    private var currencyLabel: String {
        currency.isEmpty || currency.uppercased() == "QAR"
            ? Language.get("QAR", alter: "ر.ق")
            : currency.uppercased()
    }

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                amount
                currencyText
            }
            .fixedSize(horizontal: true, vertical: false)
            .environment(\.layoutDirection, .leftToRight)
            VStack(alignment: .leading, spacing: 2) {
                amount
                currencyText
            }
            .environment(\.layoutDirection, .leftToRight)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(POSReceiptFormat.currency(value, code: currency))
    }

    private var amount: some View {
        Text(verbatim: value.englishDigits(decimals: 2))
            .font(amountFont ?? (prominent ? AdminType.title : AdminType.headline))
            .monospacedDigit()
            .fixedSize(horizontal: false, vertical: true)
    }

    private var currencyText: some View {
        Text(currencyLabel)
            .font(prominent ? AdminType.subheadline : AdminType.captionBold)
            .fixedSize(horizontal: false, vertical: true)
    }
}

private func proformaDoublePrice(_ priceString: String) -> Double {
    ProformaDecimal.parse(priceString, scale: 2).map { NSDecimalNumber(decimal: $0).doubleValue } ?? 0.0
}

// MARK: - Date Horizons & Filter Enums

enum ProformaDateHorizon: String, CaseIterable, Identifiable {
    case all = "all"
    case today = "today"
    case yesterday = "yesterday"
    case week = "week"
    case month = "month"

    var id: String { rawValue }

    var localizedTitle: String {
        switch self {
        case .all: return Language.get("Proforma_Journal_AllInvoices", alter: "كل الفواتير")
        case .today: return Language.get("POS_Horizon_Today", alter: "اليوم")
        case .yesterday: return Language.get("POS_Horizon_Yesterday", alter: "أمس")
        case .week: return Language.get("POS_Journal_Last7Days", alter: "آخر ٧ أيام")
        case .month: return Language.get("POS_Journal_Last30Days", alter: "آخر ٣٠ يومًا")
        }
    }
}

enum ProformaStatusFilter: String, CaseIterable, Identifiable {
    case all = "all"
    case draft = "draft"
    case issued = "issued"
    case converted = "converted"
    case cancelled = "cancelled"

    var id: String { rawValue }

    var localizedTitle: String {
        switch self {
        case .all: return Language.get("Proforma_Filter_All", alter: "كل الحالات")
        case .draft: return Language.get("Proforma_Status_draft", alter: "مسودة")
        case .issued: return Language.get("Proforma_Status_issued", alter: "صادرة")
        case .converted: return Language.get("Proforma_Status_converted", alter: "محولة لبيع")
        case .cancelled: return Language.get("Proforma_Status_cancelled", alter: "ملغاة")
        }
    }
}

private struct ProformaHistoryDayGroup: Identifiable {
    let day: Date?
    let invoices: [ProformaInvoice]
    var id: String { day.map { String($0.timeIntervalSince1970) } ?? "undated" }

    var localizedTitle: String {
        guard let day else { return Language.get("POS_Journal_Undated", alter: "التاريخ غير متوفر") }
        if Calendar.current.isDateInToday(day) { return Language.get("POS_Horizon_Today", alter: "اليوم") }
        if Calendar.current.isDateInYesterday(day) { return Language.get("POS_Horizon_Yesterday", alter: "أمس") }
        return day.formatted(
            Date.FormatStyle(date: .complete, time: .omitted)
                .locale(Locale(identifier: Language.isRTL() ? "ar_QA" : "en_US"))
        )
    }

    static func make(from invoices: [ProformaInvoice]) -> [Self] {
        let calendar = Calendar.current
        let groups = Dictionary(grouping: invoices) { inv in
            calendar.startOfDay(for: inv.issuedAt ?? inv.createdAt)
        }
        return groups.map { Self(day: $0.key, invoices: $0.value) }
            .sorted {
                switch ($0.day, $1.day) {
                case let (lhs?, rhs?): return lhs > rhs
                case (_?, nil): return true
                default: return false
                }
            }
    }
}

// MARK: - Dossier Status Kinds

enum ProformaDossierStatusKind {
    case draft
    case issued
    case converted
    case cancelled
    case expired

    var localizedTitle: String {
        switch self {
        case .draft: return Language.get("Proforma_Status_draft", alter: "مسودة غير صادرة")
        case .issued: return Language.get("Proforma_Status_issued", alter: "فاتورة صادرة وسارية")
        case .converted: return Language.get("Proforma_Status_converted", alter: "محولة إلى بيع نقدي")
        case .cancelled: return Language.get("Proforma_Status_cancelled", alter: "فاتورة ملغاة ومبطلة")
        case .expired: return Language.get("Proforma_Status_expired", alter: "منتهية الصلاحية")
        }
    }

    var iconName: String {
        switch self {
        case .draft: return "pencil.circle.fill"
        case .issued: return "checkmark.seal.fill"
        case .converted: return "bag.fill.badge.checkmark"
        case .cancelled: return "xmark.octagon.fill"
        case .expired: return "clock.badge.xmark.fill"
        }
    }

    var tintColor: Color {
        switch self {
        case .draft: return AdminSurface.amber
        case .issued: return Color(uiColor: .systemBlue)
        case .converted: return AdminSurface.emerald
        case .cancelled: return AdminSurface.danger
        case .expired: return Color(uiColor: .systemRed)
        }
    }

    static func resolve(for invoice: ProformaInvoice) -> ProformaDossierStatusKind {
        if invoice.status == .cancelled { return .cancelled }
        if invoice.status == .converted { return .converted }
        if invoice.isExpired { return .expired }
        if invoice.status == .issued { return .issued }
        return .draft
    }
}

// MARK: - WhatsApp Digital Proforma Dispatcher

@MainActor
enum ProformaWhatsAppSender {
    static let brandColor = POSReceiptWhatsAppSender.brandColor

    static func buildMessage(for invoice: ProformaInvoice) -> String {
        let isRTL = Language.isRTL()
        let formattedID = invoice.displayNumber
        let customerName = invoice.customer?.name ?? ""
        let validUntil = invoice.validUntil ?? ""
        let totalFormatted = POSReceiptFormat.currency(Double(invoice.totals.totalMinor) / 100.0, code: invoice.currency)

        if isRTL {
            let greeting = !customerName.isEmpty ? "مرحباً بك يا \(customerName) في بيور بتس 🐾" : "مرحباً بكم في بيور بتس 🐾"
            let invoiceSnippet = !formattedID.isEmpty ? " (فاتورة مبدئية رقم: \(formattedID))" : ""
            let validitySnippet = !validUntil.isEmpty ? "\nصالحة حتى: \(validUntil)" : ""

            return """
            \(greeting)
            نسعد بخدمتكم وتجهيز هذا العرض لأليفكم ✨

            مرفق الفاتورة المبدئية الإلكترونية\(invoiceSnippet) 📄\(validitySnippet)
            المبلغ الإجمالي: \(totalFormatted)

            شاكرين ومقدّرين ثقتكم واختياركم بيور بتس 🤍

            بيور بتس | رعاية تليق بأليفك
            📞 خدمة العملاء: +974 5999 7720
            🌐 https://pure-pets.net
            """
        } else {
            let greeting = !customerName.isEmpty ? "Hello \(customerName), welcome to Pure Pets 🐾" : "Welcome to Pure Pets 🐾"
            let invoiceSnippet = !formattedID.isEmpty ? " (Proforma Invoice #\(formattedID))" : ""
            let validitySnippet = !validUntil.isEmpty ? "\nValid until: \(validUntil)" : ""

            return """
            \(greeting)
            We are pleased to prepare this commercial quote for your pet ✨

            Attached is your electronic proforma invoice\(invoiceSnippet) 📄\(validitySnippet)
            Total Amount: \(totalFormatted)

            Thank you for choosing Pure Pets! 🤍

            Pure Pets | Care Fitting Your Pet
            📞 Customer Care: +974 5999 7720
            🌐 https://pure-pets.net
            """
        }
    }

    @discardableResult
    static func send(for invoice: ProformaInvoice, onError: ((String) -> Void)? = nil) -> Bool {
        let message = buildMessage(for: invoice)

        // 1. Render PDF page to image and put on pasteboard
        if let snapshot = try? makeSnapshot(for: invoice),
           let pdfData = try? PPProformaPDFRenderer.render(snapshot: snapshot),
           let image = POSReceiptPDFExporter.renderPDFPageToImage(pdfData: pdfData) {
            UIPasteboard.general.image = image
        }

        // 2. Feedback
        UINotificationFeedbackGenerator().notificationOccurred(.success)

        // 3. Format & Normalize Phone Number
        let rawPhone = invoice.customer?.phone ?? ""
        var cleanPhone = rawPhone.compactMap { character -> String? in
            guard let digit = character.wholeNumberValue else { return nil }
            return String(digit)
        }.joined()
        if cleanPhone.hasPrefix("00") { cleanPhone.removeFirst(2) }
        if cleanPhone.hasPrefix("0") && cleanPhone.count == 9 { cleanPhone.removeFirst() }
        if !cleanPhone.hasPrefix("974") && cleanPhone.count == 8 { cleanPhone = "974" + cleanPhone }
        if cleanPhone.count < 8 { cleanPhone = "" }

        // 4. Safely encode message
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: "+&#=")
        let encodedText = message.addingPercentEncoding(withAllowedCharacters: allowed) ?? ""

        let nativeURL: URL?
        let webURL: URL?

        if !cleanPhone.isEmpty {
            nativeURL = URL(string: "whatsapp://send?phone=\(cleanPhone)&text=\(encodedText)")
            webURL = URL(string: "https://wa.me/\(cleanPhone)?text=\(encodedText)")
        } else {
            nativeURL = URL(string: "whatsapp://send?text=\(encodedText)")
            webURL = URL(string: "https://api.whatsapp.com/send?text=\(encodedText)")
        }

        if let nativeURL, UIApplication.shared.canOpenURL(nativeURL) {
            UIApplication.shared.open(nativeURL, options: [:], completionHandler: nil)
            return true
        } else if let webURL, UIApplication.shared.canOpenURL(webURL) {
            UIApplication.shared.open(webURL, options: [:], completionHandler: nil)
            return true
        } else {
            let errorMsg = Language.get("POS_History_WhatsAppUnavailable", alter: "ثبّت واتساب على هذا الجهاز لمشاركة الفاتورة.")
            onError?(errorMsg)
            return false
        }
    }

    static func makeSnapshot(for invoice: ProformaInvoice) throws -> PPProformaPDFSnapshot {
        let branchTitle = invoice.branchName.isEmpty
            ? (BranchContextStore.shared.activeBranch?.localizedName() ?? "بيور بتس")
            : invoice.branchName
        return PPProformaPDFSnapshot(
            id: invoice.id,
            number: invoice.displayNumber,
            revision: invoice.version,
            status: invoice.status.rawValue,
            statusTitle: invoice.status.title,
            branchName: branchTitle,
            currency: invoice.currency,
            currencyDigits: 2,
            customerName: invoice.customer?.name ?? Language.get("Proforma_NoCustomer", alter: "لم يُحدّد العميل"),
            customerPhone: invoice.customer?.phone ?? "",
            customerEmail: invoice.customer?.email ?? "",
            validUntil: ProformaWire.validityDate(invoice.validUntil),
            issuedAt: invoice.issuedAt ?? invoice.createdAt,
            notes: invoice.notes,
            lines: invoice.items.map { line in
                PPProformaPDFLine(
                    title: line.name,
                    code: line.sku.isEmpty ? line.barcode : line.sku,
                    unit: line.unitIds.isEmpty ? line.groupName : String(format: pf("Proforma_ExactUnits"), line.unitIds.count),
                    quantity: ProformaDecimal.parse(line.quantity, scale: 3) ?? 0,
                    unitPrice: ProformaDecimal.parse(line.unitPrice, scale: 2) ?? 0,
                    discount: ProformaDecimal.minor(line.lineDiscountMinor + line.globalDiscountMinor),
                    tax: ProformaDecimal.minor(line.taxMinor),
                    total: ProformaDecimal.minor(line.totalMinor)
                )
            },
            subtotal: ProformaDecimal.minor(invoice.totals.subtotalMinor),
            discount: ProformaDecimal.minor(invoice.totals.lineDiscountMinor + invoice.totals.discountMinor),
            tax: ProformaDecimal.minor(invoice.totals.taxMinor),
            total: ProformaDecimal.minor(invoice.totals.totalMinor)
        )
    }

    static func makeSnapshot(for draft: ProformaDraft) throws -> PPProformaPDFSnapshot {
        let branchTitle = BranchContextStore.shared.activeBranch?.localizedName() ?? "بيور بتس"
        let lines: [PPProformaPDFLine] = draft.items.map { line in
            PPProformaPDFLine(
                title: line.name,
                code: line.sku.isEmpty ? line.barcode : line.sku,
                unit: line.unitIds.isEmpty ? line.groupName : String(format: pf("Proforma_ExactUnits"), line.unitIds.count),
                quantity: ProformaDecimal.parse(line.quantity, scale: 3) ?? 0,
                unitPrice: ProformaDecimal.parse(line.unitPrice, scale: 2) ?? 0,
                discount: ProformaDecimal.minor(line.lineDiscountMinor + line.globalDiscountMinor),
                tax: ProformaDecimal.minor(line.taxMinor),
                total: ProformaDecimal.minor(line.totalMinor)
            )
        }
        let subtotal = lines.reduce(Decimal.zero) { $0 + ($1.quantity * $1.unitPrice) }
        let discount = lines.reduce(Decimal.zero) { $0 + $1.discount }
        let tax = lines.reduce(Decimal.zero) { $0 + $1.tax }
        let total = lines.reduce(Decimal.zero) { $0 + $1.total }

        return PPProformaPDFSnapshot(
            id: draft.invoiceID ?? "draft",
            number: draft.displayNumber ?? Language.get("Proforma_NewDraft", alter: "مسودة جديدة"),
            revision: draft.version ?? 1,
            status: "draft",
            statusTitle: Language.get("Proforma_Draft", alter: "مسودة"),
            branchName: branchTitle,
            currency: draft.currency,
            currencyDigits: 2,
            customerName: draft.customer?.name ?? Language.get("Proforma_NoCustomer", alter: "لم يُحدّد العميل"),
            customerPhone: draft.customer?.phone ?? "",
            customerEmail: draft.customer?.email ?? "",
            validUntil: ProformaWire.validityDate(draft.validUntil),
            issuedAt: Date(),
            notes: draft.notes,
            lines: lines,
            subtotal: subtotal,
            discount: discount,
            tax: tax,
            total: total
        )
    }
}

// MARK: - MainKinds Fauna Model & Provider

struct PFMainKindItem: Identifiable, Hashable, Sendable {
    let id: Int
    let documentID: String
    let nameAr: String
    let nameEn: String
    let imageUrl: String?
    let iconName: String?
    let petColorHex: String?

    var localizedName: String {
        Language.isRTL() ? (nameAr.isEmpty ? nameEn : nameAr) : (nameEn.isEmpty ? nameAr : nameEn)
    }

    var themeColor: Color {
        if let hex = petColorHex, let color = Color(hex: hex) { return color }
        switch id {
        case 1: return Color(red: 0.92, green: 0.52, blue: 0.22)
        case 2: return Color(red: 0.58, green: 0.38, blue: 0.88)
        case 3: return Color(red: 0.16, green: 0.72, blue: 0.76)
        case 4: return Color(red: 0.22, green: 0.65, blue: 0.95)
        case 5: return Color(red: 0.32, green: 0.78, blue: 0.46)
        case 6: return Color(red: 0.55, green: 0.68, blue: 0.24)
        default: return AdminSurface.primary
        }
    }
}

@MainActor
final class ProformaMainKindsProvider: ObservableObject {
    static let shared = ProformaMainKindsProvider()
    @Published private(set) var kinds: [PFMainKindItem] = []
    @Published private(set) var isLoaded = false

    init() { load() }

    func load() {
        if let raw = MainKindsArrayManager.shared().mainKindsArray as? [MainKindsModel], !raw.isEmpty {
            parse(raw)
            return
        }
        if let raw = AppManager.shared().mainKindsArray as? [MainKindsModel], !raw.isEmpty {
            parse(raw)
            return
        }
        MainKindsArrayManager.shared().loadMainDataCompletionHandler { [weak self] _ in
            Task { @MainActor in
                if let raw = MainKindsArrayManager.shared().mainKindsArray as? [MainKindsModel], !raw.isEmpty {
                    self?.parse(raw)
                }
            }
        }
    }

    private func parse(_ models: [MainKindsModel]) {
        var items: [PFMainKindItem] = []
        for m in models {
            let item = PFMainKindItem(
                id: Int(m.id),
                documentID: m.documentID ?? "\(m.id)",
                nameAr: m.kindNameAr ?? "",
                nameEn: m.kindNameEn ?? "",
                imageUrl: m.kindImageUrl,
                iconName: m.kindIconName,
                petColorHex: m.petColor
            )
            items.append(item)
        }
        self.kinds = items
        self.isLoaded = !items.isEmpty
    }
}

// MARK: - Root Proforma Journal View (Main Screen)

@MainActor
struct AdminProformaInvoicesView: View {
    let session: AdminSession
    var onDismiss: (() -> Void)? = nil

    @ObservedObject private var branchStore = BranchContextStore.shared
    @StateObject private var store: ProformaInvoiceStore
    @StateObject private var kindsProvider = ProformaMainKindsProvider.shared

    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // Presentation States
    @State private var selectedDossierInvoice: ProformaInvoice? = nil
    @State private var invoiceForConversion: ProformaInvoice? = nil
    @State private var invoiceForCancel: ProformaInvoice? = nil
    @State private var actualReceiptForView: POSCompletedReceipt? = nil
    @State private var actualReceiptLoading = false
    @State private var previewDocument: ProformaPreviewDocument? = nil
    @State private var shareDocument: PPProformaPDFDocument? = nil
    @State private var pendingShare: ProformaPreviewDocument? = nil

    // Editor & Catalog States
    @State private var isShowingEditor = false
    @State private var isPeriodDetailsExpanded = false
    @State private var copyToastText: String? = nil
    @State private var copyToastID = UUID()
    @FocusState private var isSearchFocused: Bool
    @ScaledMetric(relativeTo: .body) private var searchControlHeight: CGFloat = 44

    // Filtering
    @State private var selectedHorizon: ProformaDateHorizon = .all
    @State private var selectedStatusFilter: ProformaStatusFilter = .all
    @State private var searchQuery = ""
    @State private var localError: String? = nil

    private var canWrite: Bool { session.hasPermission("pos.sell") }
    private var activeBranchID: String { branchStore.activeBranch?.branchID ?? session.branchId ?? "" }

    init(session: AdminSession, onDismiss: (() -> Void)? = nil) {
        self.session = session
        self.onDismiss = onDismiss
        _store = StateObject(wrappedValue: ProformaInvoiceStore(actorUID: session.uid))
    }

    private var filteredInvoices: [ProformaInvoice] {
        var list = store.invoices

        // Status Filter
        if selectedStatusFilter != .all {
            list = list.filter { $0.status.rawValue == selectedStatusFilter.rawValue }
        }

        // Date Horizon Filter
        let calendar = Calendar.current
        let now = Date()
        switch selectedHorizon {
        case .all:
            break
        case .today:
            list = list.filter { calendar.isDateInToday($0.issuedAt ?? $0.createdAt) }
        case .yesterday:
            list = list.filter { calendar.isDateInYesterday($0.issuedAt ?? $0.createdAt) }
        case .week:
            if let start = calendar.date(byAdding: .day, value: -7, to: now) {
                list = list.filter { ($0.issuedAt ?? $0.createdAt) >= start }
            }
        case .month:
            if let start = calendar.date(byAdding: .day, value: -30, to: now) {
                list = list.filter { ($0.issuedAt ?? $0.createdAt) >= start }
            }
        }

        // Search Query
        let q = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if !q.isEmpty {
            list = list.filter {
                $0.number.lowercased().contains(q) ||
                $0.displayNumber.lowercased().contains(q) ||
                ($0.customer?.name.lowercased().contains(q) ?? false) ||
                ($0.customer?.phone.contains(q) ?? false) ||
                $0.items.contains(where: { $0.name.lowercased().contains(q) || $0.sku.lowercased().contains(q) })
            }
        }
        return list
    }

    private var totalPeriodVolume: Double {
        let minorSum = filteredInvoices.reduce(0) { $0 + $1.totals.totalMinor }
        return Double(minorSum) / 100.0
    }

    private var totalItemsQuoted: Int {
        filteredInvoices.reduce(0) { $0 + $1.items.count }
    }

    private var draftsVolume: Double {
        let minor = filteredInvoices.filter { $0.status == .draft }.reduce(0) { $0 + $1.totals.totalMinor }
        return Double(minor) / 100.0
    }

    private var issuedVolume: Double {
        let minor = filteredInvoices.filter { $0.status == .issued }.reduce(0) { $0 + $1.totals.totalMinor }
        return Double(minor) / 100.0
    }

    private var convertedVolume: Double {
        let minor = filteredInvoices.filter { $0.status == .converted }.reduce(0) { $0 + $1.totals.totalMinor }
        return Double(minor) / 100.0
    }

    private var cancelledVolume: Double {
        let minor = filteredInvoices.filter { $0.status == .cancelled }.reduce(0) { $0 + $1.totals.totalMinor }
        return Double(minor) / 100.0
    }

    var body: some View {
        ZStack {
            AdminSurface.surface.ignoresSafeArea()

            VStack(spacing: 0) {
                navigationHeaderView

                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 24) {
                        PPAdminBranchSwitcherBar(style: .journal, horizontalPadding: 0)
                        periodStatement
                        receiptLocator
                        ledgerSection
                    }
                    .frame(maxWidth: 760, alignment: .leading)
                    .padding(.horizontal, AdminSpacing.screenMargin)
                    .padding(.top, 20)
                    .padding(.bottom, 24)
                    .frame(maxWidth: .infinity)
                }
                .scrollDismissesKeyboard(.interactively)
                .refreshable {
                    await store.load(branchId: activeBranchID)
                }
            }

            // Copy Toast Notification
            if let toast = copyToastText {
                VStack {
                    Spacer()
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(Color(uiColor: .ppSuccess))
                        Text(toast)
                            .font(AdminType.captionBold)
                            .foregroundColor(.white)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(Color.black.opacity(0.85), in: Capsule())
                    .padding(.bottom, 16)
                    .transition(reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity))
                    .accessibilityElement(children: .combine)
                    .allowsHitTesting(false)
                }
                .zIndex(100)
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if canWrite && !isSearchFocused {
                newDraftRail
            }
        }
        .environment(\.layoutDirection, Language.isRTL() ? .rightToLeft : .leftToRight)
        .environment(\.locale, Locale(identifier: Language.isRTL() ? "ar_QA" : "en_US"))
        .task(id: copyToastID) {
            guard let text = copyToastText else { return }
            do { try await Task.sleep(nanoseconds: 2_200_000_000) } catch { return }
            if copyToastText == text {
                withAnimation(reduceMotion ? nil : .easeOut(duration: 0.18)) { copyToastText = nil }
            }
        }
        .task(id: activeBranchID) {
            guard session.hasAnyPermission(["pos.view", "pos.sell"]) else { return }
            await store.load(branchId: activeBranchID)
        }
        // Full Screen Transaction Dossier
        .fullScreenCover(item: $selectedDossierInvoice) { invoice in
            ProformaTransactionDossierSheet(
                invoice: invoice,
                session: session,
                store: store,
                onPrint: {},
                onWhatsApp: {
                    ProformaWhatsAppSender.send(for: invoice) { errMsg in
                        showToast(errMsg)
                    }
                },
                onEdit: {
                    selectedDossierInvoice = nil
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        Task {
                            await store.open(invoice)
                            isShowingEditor = true
                        }
                    }
                },
                onConvert: {
                    selectedDossierInvoice = nil
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        invoiceForConversion = invoice
                    }
                },
                onCancel: {
                    selectedDossierInvoice = nil
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        promptCancelInvoice(invoice)
                    }
                },
                onViewReceipt: {
                    fetchActualSale(for: invoice)
                },
                onCopied: { text in
                    showToast(text)
                }
            )
        }
        // Full Screen Proforma Studio Editor
        .fullScreenCover(isPresented: $isShowingEditor) {
            ProformaEditorStudioSheet(
                session: session,
                store: store,
                kindsProvider: kindsProvider,
                activeBranchID: activeBranchID,
                canWrite: canWrite,
                onClose: {
                    isShowingEditor = false
                },
                onPreview: { _ in },
                onConvert: { inv in
                    isShowingEditor = false
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        invoiceForConversion = inv
                    }
                },
                onCancelInvoice: { inv in
                    isShowingEditor = false
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        promptCancelInvoice(inv)
                    }
                },
                onToast: { msg in
                    showToast(msg)
                }
            )
        }
        // Conversion Sheet
        .sheet(item: $invoiceForConversion) { invoice in
            ProformaConversionSheet(
                invoice: invoice,
                store: store,
                onSuccess: { completedReceipt in
                    invoiceForConversion = nil
                    showToast(Language.get("Proforma_Convert_SuccessTitle", alter: "تم تحويل الفاتورة إلى بيع بنجاح"))
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                        actualReceiptForView = completedReceipt
                    }
                }
            )
        }
        // Cancel Confirmation Sheet
        .sheet(item: $invoiceForCancel) { invoice in
            ProformaCancelConfirmationSheet(
                invoice: invoice,
                store: store,
                onSuccess: {
                    invoiceForCancel = nil
                    showToast(Language.get("Proforma_Cancel_SuccessTitle", alter: "تم إلغاء الفاتورة المبدئية"))
                }
            )
        }
        // Actual POS Sale Receipt Sheet
        .sheet(item: $actualReceiptForView) { receipt in
            POSCompletedReceiptSheet(receipt: receipt)
        }
        // PDF Preview & Share Sheet
        .proformaPDFPresenter(previewDocument: $previewDocument, shareDocument: $shareDocument)
        .enableSwipeToPop {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            if let onDismiss { onDismiss() } else { dismiss() }
        }
    }

    // MARK: - Navigation Header

    private var navigationHeaderView: some View {
        HStack(alignment: .center, spacing: 12) {
            AdminSquircleBackButton {
                isSearchFocused = false
                if let onDismiss { onDismiss() } else { dismiss() }
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(Language.get("Proforma_Title", alter: "الفواتير المبدئية"))
                    .font(PPBeirutiFont.bold(20, relativeTo: .title3))
                    .foregroundStyle(AdminSurface.primaryText)
                    .accessibilityAddTraits(.isHeader)
                if !dynamicTypeSize.isAccessibilitySize {
                    Text(loadStatus)
                        .font(AdminType.caption)
                        .foregroundStyle(AdminSurface.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Button {
                isSearchFocused = false
                Task { await store.load(branchId: activeBranchID) }
            } label: {
                Group {
                    if store.isLoading {
                        ProgressView().tint(AdminSurface.primary)
                    } else {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 19, weight: .medium))
                    }
                }
                .frame(width: 44, height: 44)
            }
            .buttonStyle(POSReceiptActionStyle(cornerRadius: 14))
            .disabled(store.isLoading)
            .accessibilityLabel(Language.get("Refresh", alter: "تحديث"))
            .accessibilityValue(loadStatus)
        }
        .padding(.horizontal, AdminSpacing.screenMargin)
        .padding(.top, 0)
        .padding(.bottom, 8)
        .frame(maxWidth: 1040)
    }

    private var loadStatus: String {
        if store.isLoading { return Language.get("Proforma_Loading", alter: "جارٍ تحميل فواتير الفرع…") }
        if store.error != nil { return Language.get("Proforma_Error_Title", alter: "تعذر تحميل الفواتير") }
        return Language.get("Proforma_Loaded_Status", alter: "تم تحميل فواتير الفرع")
    }

    // MARK: - Period Statement

    private var periodStatement: some View {
        VStack(alignment: .leading, spacing: 14) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .center, spacing: 16) {
                    netVolumeLabel
                    Spacer(minLength: 8)
                    periodControl
                }
                VStack(alignment: .leading, spacing: 4) {
                    netVolumeLabel
                    periodControl
                }
            }
            if !store.isLoading && store.error == nil {
                POSJournalAmount(value: totalPeriodVolume, currency: "QAR", prominent: true)
                    .foregroundStyle(AdminSurface.primary)
                Text(String(
                    format: Language.get("Proforma_Journal_ActivityFormat", alter: "%@ فواتير مبدئية · %@ قطع مدرجة"),
                    filteredInvoices.count.englishDigits,
                    totalItemsQuoted.englishDigits
                ))
                .font(AdminType.subheadline)
                .foregroundStyle(AdminSurface.secondaryText)
                .fixedSize(horizontal: false, vertical: true)

                DisclosureGroup(isExpanded: $isPeriodDetailsExpanded) {
                    periodFacts
                        .padding(.top, 12)
                        .padding(.bottom, 4)
                } label: {
                    Text(Language.get("Proforma_Journal_PeriodDetails", alter: "تفاصيل الفترة"))
                        .font(AdminType.subheadlineBold)
                        .frame(minHeight: 44, alignment: .leading)
                }
                .tint(AdminSurface.primary)
                .animation(reduceMotion ? nil : .easeInOut(duration: 0.18), value: isPeriodDetailsExpanded)
            } else if store.isLoading {
                HStack(spacing: 12) {
                    ProgressView().tint(AdminSurface.primary)
                    Text(Language.get("Proforma_Loading", alter: "جارٍ تحميل فواتير الفرع…"))
                        .font(AdminType.body)
                        .foregroundStyle(AdminSurface.secondaryText)
                }
                .padding(.vertical, 12)
            }
            Text(Language.get("Proforma_Journal_Scope", alter: "إجماليات الفواتير المبدئية محسوبة من أحدث الفواتير المسجلة لهذا الفرع."))
                .font(AdminType.caption)
                .foregroundStyle(AdminSurface.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
            Divider().overlay(AdminSurface.hairline)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var netVolumeLabel: some View {
        Text(Language.get("Proforma_Journal_NetVolume", alter: "إجمالي عروض الأسعار"))
            .font(AdminType.subheadlineBold)
            .foregroundStyle(AdminSurface.primaryText)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var periodControl: some View {
        Menu {
            Picker(Language.get("POS_Journal_Period", alter: "الفترة"), selection: $selectedHorizon) {
                ForEach(ProformaDateHorizon.allCases) { horizon in
                    Text(horizon.localizedTitle).tag(horizon)
                }
            }
        } label: {
            Label {
                Text(selectedHorizon.localizedTitle)
                    .font(AdminType.subheadlineBold)
            } icon: {
                Image(systemName: "calendar")
            }
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 10)
            .frame(minHeight: 44)
            .foregroundStyle(AdminSurface.primary)
            .background(AdminSurface.backgroundSecondary, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .accessibilityLabel(Language.get("POS_Journal_Period", alter: "الفترة"))
        .accessibilityValue(selectedHorizon.localizedTitle)
    }

    @ViewBuilder
    private var periodFacts: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 18) { periodFactContent }
        } else {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 160), spacing: 24, alignment: .leading)], alignment: .leading, spacing: 18) {
                periodFactContent
            }
        }
    }

    @ViewBuilder
    private var periodFactContent: some View {
        periodFact(title: Language.get("Proforma_Status_draft", alter: "المسودات"), amount: draftsVolume)
        periodFact(title: Language.get("Proforma_Status_issued", alter: "الصادرة"), amount: issuedVolume)
        periodFact(title: Language.get("Proforma_Status_converted", alter: "المحولة لبيع"), amount: convertedVolume)
        periodFact(title: Language.get("Proforma_Status_cancelled", alter: "الملغاة"), amount: cancelledVolume)
    }

    private func periodFact(title: String, amount: Double) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(AdminType.caption)
                .foregroundStyle(AdminSurface.secondaryText)
            POSJournalAmount(value: amount, currency: "QAR")
                .foregroundStyle(AdminSurface.primaryText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    // MARK: - Receipt Locator (Search & Filter Bar)

    private var receiptLocator: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(AdminSurface.secondaryText)
                    .accessibilityHidden(true)
                TextField(Language.get("Proforma_Journal_Search", alter: "ابحث عن فاتورة مبدئية"), text: $searchQuery, prompt: Text(""))
                    .font(AdminType.body)
                    .foregroundStyle(AdminSurface.primaryText)
                    .multilineTextAlignment(.leading)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.search)
                    .focused($isSearchFocused)
                    .onSubmit { isSearchFocused = false }
                    .frame(minHeight: searchControlHeight)
                    .overlay(alignment: .leading) {
                        if searchQuery.isEmpty {
                            Text(Language.get("Proforma_Journal_Search", alter: "ابحث عن فاتورة مبدئية"))
                                .font(AdminType.body)
                                .foregroundStyle(AdminSurface.secondaryText)
                                .multilineTextAlignment(.leading)
                                .fixedSize(horizontal: false, vertical: true)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .allowsHitTesting(false)
                                .accessibilityHidden(true)
                        }
                    }
                    .environment(\.layoutDirection, Language.isRTL() ? .rightToLeft : .leftToRight)
                    .accessibilityLabel(Language.get("Proforma_Journal_Search", alter: "ابحث عن فاتورة مبدئية"))
                    .accessibilityHint(Language.get("Proforma_Journal_SearchHint", alter: "رقم الفاتورة، العميل، الهاتف أو الصنف"))
                if !searchQuery.isEmpty {
                    Button { searchQuery = "" } label: {
                        Image(systemName: "xmark.circle.fill")
                            .frame(width: 44, height: 44)
                    }
                    .buttonStyle(POSJournalButtonStyle())
                    .accessibilityLabel(Language.get("Clear", alter: "مسح"))
                }
            }
            .padding(.leading, 14)
            .padding(.trailing, searchQuery.isEmpty ? 14 : 2)
            .padding(.vertical, 4)
            .frame(minHeight: 52)
            .background(AdminSurface.backgroundSecondary, in: RoundedRectangle(cornerRadius: 12, style: .continuous))

            HStack(alignment: .center, spacing: 12) {
                Menu {
                    Picker(Language.get("POS_Journal_Status", alter: "الحالة"), selection: $selectedStatusFilter) {
                        ForEach(ProformaStatusFilter.allCases) { filter in
                            Text(filter.localizedTitle).tag(filter)
                        }
                    }
                } label: {
                    filterLabel(
                        title: Language.get("POS_Journal_Status", alter: "الحالة"),
                        value: selectedStatusFilter.localizedTitle,
                        isFiltered: selectedStatusFilter != .all
                    )
                }
                .accessibilityLabel(Language.get("POS_Journal_Status", alter: "الحالة"))
                .accessibilityValue(selectedStatusFilter.localizedTitle)

                Menu {
                    Picker(Language.get("POS_Journal_Period", alter: "الفترة"), selection: $selectedHorizon) {
                        ForEach(ProformaDateHorizon.allCases) { horizon in
                            Text(horizon.localizedTitle).tag(horizon)
                        }
                    }
                } label: {
                    filterLabel(
                        title: Language.get("POS_Journal_Period", alter: "الفترة"),
                        value: selectedHorizon.localizedTitle,
                        isFiltered: selectedHorizon != .all
                    )
                }
                .accessibilityLabel(Language.get("POS_Journal_Period", alter: "الفترة"))
                .accessibilityValue(selectedHorizon.localizedTitle)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if hasActiveFilters {
                Button {
                    isSearchFocused = false
                    selectedStatusFilter = .all
                    selectedHorizon = .all
                    searchQuery = ""
                } label: {
                    Label(Language.get("POS_Journal_ClearFilters", alter: "مسح الفلاتر"), systemImage: "xmark")
                        .font(AdminType.captionBold)
                        .frame(minHeight: 44)
                }
                .buttonStyle(POSJournalButtonStyle())
            }
        }
    }

    private var hasActiveFilters: Bool {
        selectedStatusFilter != .all || selectedHorizon != .all || !searchQuery.isEmpty
    }

    private func filterLabel(title: String, value: String, isFiltered: Bool) -> some View {
        HStack(alignment: .center, spacing: 8) {
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(AdminType.caption).foregroundStyle(AdminSurface.secondaryText)
                Text(value).font(AdminType.subheadlineBold)
            }
            Image(systemName: "chevron.down").font(.system(size: 10, weight: .semibold))
                .accessibilityHidden(true)
        }
        .foregroundStyle(isFiltered ? AdminSurface.primary : AdminSurface.primaryText)
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
        .frame(minHeight: 44, alignment: .leading)
        .background(AdminSurface.backgroundSecondary, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .contentShape(Rectangle())
    }

    // MARK: - Ledger Section

    @ViewBuilder
    private var ledgerSection: some View {
        if let error = store.error {
            journalNotice(
                symbol: "exclamationmark.triangle",
                title: Language.get("Proforma_Error_Title", alter: "تعذر تحميل فواتير هذا الفرع"),
                message: error
            )
            Button {
                Task { await store.load(branchId: activeBranchID) }
            } label: {
                Label(Language.get("Retry", alter: "إعادة المحاولة"), systemImage: "arrow.clockwise")
                    .font(AdminType.headline)
                    .padding(.horizontal, 18)
                    .frame(minHeight: 48)
            }
            .buttonStyle(POSJournalButtonStyle(filled: true))
        } else if store.isLoading && store.invoices.isEmpty {
            EmptyView()
        } else if filteredInvoices.isEmpty {
            if store.invoices.isEmpty {
                journalNotice(
                    symbol: "doc.text.magnifyingglass",
                    title: Language.get("Proforma_Empty", alter: "لا توجد فواتير مبدئية"),
                    message: Language.get("Proforma_Empty_Detail", alter: "أنشئ مسودة جديدة، واختر عميلاً، وأضف المنتجات. يبقى المخزون متاحاً حتى تأكيد البيع.")
                )
            } else {
                journalNotice(
                    symbol: "magnifyingglass",
                    title: Language.get("Proforma_Journal_NoMatches", alter: "لا توجد فواتير مطابقة"),
                    message: Language.get("Proforma_Journal_NoMatchesHelp", alter: "غيّر البحث أو الفلاتر، أو اعرض كل فواتير هذا الفرع.")
                )
                Button {
                    isSearchFocused = false
                    selectedHorizon = .all
                    selectedStatusFilter = .all
                    searchQuery = ""
                } label: {
                    Label(Language.get("Proforma_Journal_AllInvoices", alter: "كل الفواتير"), systemImage: "clock.arrow.circlepath")
                        .font(AdminType.subheadlineBold)
                        .padding(.horizontal, 14)
                        .frame(minHeight: 48)
                }
                .buttonStyle(POSJournalButtonStyle())
            }
        } else {
            VStack(alignment: .leading, spacing: 10) {
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        invoicesHeading
                        resultCount
                        Spacer(minLength: 4)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        invoicesHeading
                        resultCount
                    }
                }

                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(ProformaHistoryDayGroup.make(from: filteredInvoices)) { group in
                        Section {
                            ForEach(group.invoices, id: \.id) { invoice in
                                ProformaTransactionCard(
                                    invoice: invoice,
                                    onTap: {
                                        isSearchFocused = false
                                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                        selectedDossierInvoice = invoice
                                    },
                                    onPrint: {
                                        isSearchFocused = false
                                        makePreview(invoice)
                                    },
                                    onCopyID: { id in
                                        UIPasteboard.general.string = id
                                        UINotificationFeedbackGenerator().notificationOccurred(.success)
                                        showToast(Language.get("Proforma_Copy_Success", alter: "تم نسخ رقم الفاتورة إلى الحافظة"))
                                    },
                                    onWhatsApp: {
                                        ProformaWhatsAppSender.send(for: invoice) { errMsg in
                                            showToast(errMsg)
                                        }
                                    }
                                )
                                Divider().overlay(AdminSurface.hairline)
                            }
                        } header: {
                            Text(group.localizedTitle)
                                .font(AdminType.captionBold)
                                .foregroundStyle(AdminSurface.secondaryText)
                                .padding(.top, 10)
                                .padding(.bottom, 4)
                                .accessibilityAddTraits(.isHeader)
                        }
                    }
                }
            }
        }
    }

    private var invoicesHeading: some View {
        Text(Language.get("Proforma_Journal_Invoices", alter: "الفواتير المبدئية"))
            .font(AdminType.title3)
            .foregroundStyle(AdminSurface.primaryText)
            .accessibilityAddTraits(.isHeader)
    }

    private var resultCount: some View {
        Text(String(format: Language.get("Proforma_Journal_ResultCountFormat", alter: "%@ فواتير مطابقة"), filteredInvoices.count.englishDigits))
            .font(AdminType.caption)
            .foregroundStyle(AdminSurface.secondaryText)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func journalNotice(symbol: String, title: String, message: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(AdminSurface.primary)
                .accessibilityHidden(true)
            Text(title)
                .font(AdminType.title2)
                .foregroundStyle(AdminSurface.primaryText)
                .accessibilityAddTraits(.isHeader)
            Text(message)
                .font(AdminType.body)
                .foregroundStyle(AdminSurface.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 14)
    }

    // MARK: - New Draft Rail (Bottom Safe Area Action)

    private var newDraftRail: some View {
        VStack(spacing: 0) {
            Divider().overlay(AdminSurface.hairline)
            Button {
                guard canWrite, branchStore.activeBranch != nil else { return }
                isSearchFocused = false
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                store.clearSelection()
                store.createDraft()
                isShowingEditor = true
            } label: {
                Label(Language.get("Proforma_Journal_NewDraft", alter: "فاتورة مبدئية جديدة"), systemImage: "plus")
                    .font(AdminType.headline)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity, minHeight: 48)
            }
            .buttonStyle(POSJournalButtonStyle(filled: true))
            .disabled(branchStore.activeBranch == nil || store.isLocked)
            .frame(maxWidth: 520)
            .padding(.horizontal, AdminSpacing.screenMargin)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .background(AdminSurface.surface)
    }

    private func showToast(_ text: String) {
        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.18)) {
            copyToastID = UUID()
            copyToastText = text
        }
        UIAccessibility.post(notification: .announcement, argument: text)
    }

    private func makePreview(_ invoice: ProformaInvoice) {
        guard !store.isLocked else { return }
        do {
            let snapshot = try ProformaWhatsAppSender.makeSnapshot(for: invoice)
            let pdfData = try PPProformaPDFRenderer.render(snapshot: snapshot)
            previewDocument = ProformaPreviewDocument(data: pdfData, number: invoice.displayNumber)
        } catch {
            showToast(error.localizedDescription)
        }
    }

    private func fetchActualSale(for invoice: ProformaInvoice) {
        guard let txID = invoice.convertedTransactionId, !actualReceiptLoading else { return }
        actualReceiptLoading = true
        PPPOSService.shared().fetchPOSReceipt(forTransactionID: txID) { receipt, error in
            Task { @MainActor in
                actualReceiptLoading = false
                if let receipt {
                    actualReceiptForView = POSCompletedReceipt(receipt: receipt)
                } else {
                    showToast(Language.get("Proforma_Error_LoadingSale", alter: "تعذر تحميل إيصال البيع."))
                }
            }
        }
    }

    private func promptCancelInvoice(_ invoice: ProformaInvoice) {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        let title = Language.get("Proforma_CancelInvoice_Title", alter: "إلغاء الفاتورة المبدئية؟")
        let message = "\(invoice.displayNumber)\n" + Language.get("Proforma_CancelInvoice_Message", alter: "يبقى المستند المحفوظ في القائمة بحالة ملغاة. لا يُنشأ بيع ولا حركة مخزون.")
        PPAlertHelper.showDestructiveConfirmation(
            in: nil,
            title: title,
            subtitle: message,
            confirmButton: Language.get("Proforma_CancelInvoice", alter: "تأكيد إلغاء الفاتورة"),
            cancelButton: Language.get("Cancel", alter: "تراجع"),
            icon: UIImage(systemName: "xmark.octagon.fill"),
            confirmBlock: { _, didConfirm in
                guard didConfirm else { return }
                Task { @MainActor in
                    let success = await self.store.cancelInvoice(invoice)
                    if success {
                        self.showToast(Language.get("Proforma_Cancel_SuccessTitle", alter: "تم إلغاء الفاتورة المبدئية"))
                    } else if let error = self.store.error {
                        await PPAlertHelper.showError(in: nil, title: Language.get("Error", alter: "خطأ"), subtitle: error)
                    }
                }
            },
            cancelBlock: nil
        )
    }
}

// MARK: - Living Proforma Transaction Card (Following POSTransactionCard Pattern)

private struct ProformaTransactionCard: View {
    let invoice: ProformaInvoice
    let onTap: () -> Void
    let onPrint: () -> Void
    let onCopyID: (String) -> Void
    let onWhatsApp: () -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var isPreparingWhatsApp = false

    private var statusKind: ProformaDossierStatusKind {
        ProformaDossierStatusKind.resolve(for: invoice)
    }

    private var customerIdentity: String {
        let name = invoice.customer?.name.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !name.isEmpty { return name }
        let phone = invoice.customer?.phone.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !phone.isEmpty { return phone }
        return Language.get("POS_Dossier_WalkInCustomer", alter: "عميل نقدي مباشر / لم يُحدد")
    }

    private var customerIsPhone: Bool {
        let name = invoice.customer?.name.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let phone = invoice.customer?.phone.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return name.isEmpty && !phone.isEmpty
    }

    private var hasRecordedCustomer: Bool {
        let name = invoice.customer?.name.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let phone = invoice.customer?.phone.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return !name.isEmpty || !phone.isEmpty
    }

    private var itemsPreviewText: String {
        let names = invoice.items.prefix(2).map { "\($0.name) × \($0.quantity)" }
        let joined = names.joined(separator: " • ")
        if invoice.items.count > 2 {
            let extra = (invoice.items.count - 2).englishDigits
            return "\(joined) +\(extra)"
        }
        return joined.isEmpty ? Language.get("Proforma_ItemsEmpty", alter: "لا توجد عناصر مضافة") : joined
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Button(action: onTap) {
                cardContent
                    .padding(.vertical, 4)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(POSJournalButtonStyle())
            .accessibilityElement(children: .combine)
            .accessibilityHint(Language.get("Proforma_Card_TapToView", alter: "فتح تفاصيل الفاتورة وإجراءاتها"))

            copyIdentityRow
            quickActionsRow
        }
        .padding(.vertical, 12)
        .multilineTextAlignment(.leading)
    }

    private var cardContent: some View {
        VStack(alignment: .leading, spacing: 6) {
            let layout = dynamicTypeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
                : AnyLayout(HStackLayout(alignment: .top, spacing: 14))

            layout {
                Text(customerIdentity)
                    .font(hasRecordedCustomer ? AdminType.headline : AdminType.subheadline)
                    .foregroundStyle(hasRecordedCustomer ? AdminSurface.primaryText : AdminSurface.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                    .environment(\.layoutDirection, customerIsPhone ? .leftToRight : (Language.isRTL() ? .rightToLeft : .leftToRight))
                    .frame(maxWidth: .infinity, alignment: .leading)

                VStack(alignment: .leading, spacing: 2) {
                    POSJournalAmount(
                        value: Double(invoice.totals.totalMinor) / 100.0,
                        currency: invoice.currency,
                        amountFont: AdminType.title3
                    )
                    .foregroundStyle(invoice.status == .cancelled ? AdminSurface.secondaryText : AdminSurface.primaryText)
                }
            }

            ViewThatFits(in: .horizontal) {
                HStack(alignment: .center, spacing: 12) {
                    statusPill
                    validityOrTimestamp
                }
                .fixedSize(horizontal: true, vertical: false)

                VStack(alignment: .leading, spacing: 4) {
                    statusPill
                    validityOrTimestamp
                }
            }

            Text(itemsPreviewText)
                .font(AdminType.subheadline)
                .foregroundStyle(AdminSurface.secondaryText)
                .fixedSize(horizontal: false, vertical: true)

            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    itemsCount
                    if !invoice.branchName.isEmpty { branchText(invoice.branchName) }
                    reviewAffordance
                }
                .fixedSize(horizontal: true, vertical: false)

                VStack(alignment: .leading, spacing: 4) {
                    itemsCount
                    if !invoice.branchName.isEmpty { branchText(invoice.branchName) }
                    reviewAffordance
                }
            }
        }
    }

    private var statusPill: some View {
        Label(statusKind.localizedTitle, systemImage: statusKind.iconName)
            .font(AdminType.captionBold)
            .foregroundStyle(statusKind.tintColor)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var validityOrTimestamp: some View {
        Group {
            if let valid = invoice.validUntil, !valid.isEmpty {
                Label(String(format: Language.get("Proforma_ValidUntilFormat", alter: "صالحة حتى: %@"), valid), systemImage: "calendar.badge.clock")
                    .font(AdminType.caption)
                    .foregroundStyle(invoice.isExpired ? AdminSurface.danger : AdminSurface.secondaryText)
            } else {
                Text(invoice.updatedAt, style: .date)
                    .font(AdminType.caption)
                    .foregroundStyle(AdminSurface.secondaryText)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private var itemsCount: some View {
        Text(String(format: Language.get("POS_Dossier_ItemsCount", alter: "%d عنصر"), invoice.items.count))
            .font(AdminType.caption)
            .foregroundStyle(AdminSurface.secondaryText)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func branchText(_ name: String) -> some View {
        Text(name)
            .font(AdminType.caption)
            .foregroundStyle(AdminSurface.secondaryText)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var reviewAffordance: some View {
        HStack(spacing: 6) {
            Text(Language.get("Proforma_Journal_OpenInvoice", alter: "مراجعة الفاتورة"))
                .font(AdminType.captionBold)
            Image(systemName: Language.isRTL() ? "arrow.left" : "arrow.right")
                .font(.system(size: 11, weight: .medium))
                .accessibilityHidden(true)
        }
        .foregroundStyle(AdminSurface.primary)
        .fixedSize(horizontal: false, vertical: true)
    }

    private var copyIdentityRow: some View {
        Button {
            onCopyID(invoice.displayNumber)
        } label: {
            HStack(spacing: 6) {
                Text(verbatim: invoice.displayNumber)
                    .font(AdminType.caption)
                    .foregroundStyle(AdminSurface.secondaryText)
                    .environment(\.layoutDirection, .leftToRight)
                Image(systemName: "doc.on.doc")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(AdminSurface.secondaryText)
            }
            .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
    }

    private var quickActionsRow: some View {
        HStack(spacing: 8) {
            // Direct WhatsApp Button
            Button(action: onWhatsApp) {
                HStack(spacing: 6) {
                    Image("whatsapp")
                        .renderingMode(.template)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 16, height: 16)
                    Text(Language.get("WhatsApp", alter: "واتساب"))
                        .font(AdminType.captionBold)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .frame(minHeight: 40)
            }
            .buttonStyle(POSReceiptActionStyle(surface: POSReceiptWhatsAppSender.brandColor.opacity(0.12)))

            // Direct Call Customer Button (if phone exists)
            if let phone = invoice.customer?.phone, !phone.isEmpty, let url = URL(string: "tel://\(phone.filter("0123456789+".contains))") {
                Button {
                    UIApplication.shared.open(url)
                } label: {
                    Label(Language.get("Call", alter: "اتصال"), systemImage: "phone")
                        .font(AdminType.captionBold)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .frame(minHeight: 40)
                }
                .buttonStyle(POSReceiptActionStyle())
            }

            // Print / PDF Button
            Button(action: onPrint) {
                Label(Language.get("Proforma_Preview", alter: "PDF"), systemImage: "printer")
                    .font(AdminType.captionBold)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .frame(minHeight: 40)
            }
            .buttonStyle(POSReceiptActionStyle())

            Spacer()
        }
        .padding(.top, 4)
    }
}

// MARK: - Transaction Dossier Sheet (Full-Screen Dual Architecture)

struct ProformaTransactionDossierSheet: View {
    let invoice: ProformaInvoice
    let session: AdminSession
    @ObservedObject var store: ProformaInvoiceStore

    let onPrint: () -> Void
    let onWhatsApp: () -> Void
    let onEdit: () -> Void
    let onConvert: () -> Void
    let onCancel: () -> Void
    let onViewReceipt: () -> Void
    let onCopied: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.dynamicTypeSize) private var typeSize

    private var isPad: Bool {
        UIDevice.current.userInterfaceIdiom == .pad || (horizontalSizeClass == .regular && !typeSize.isAccessibilitySize)
    }

    private var statusKind: ProformaDossierStatusKind {
        ProformaDossierStatusKind.resolve(for: invoice)
    }

    @State private var previewDocument: ProformaPreviewDocument? = nil
    @State private var shareDocument: PPProformaPDFDocument? = nil

    private func makeLocalPreview() {
        guard !store.isLocked else { return }
        do {
            let snapshot = try ProformaWhatsAppSender.makeSnapshot(for: invoice)
            let pdfData = try PPProformaPDFRenderer.render(snapshot: snapshot)
            previewDocument = ProformaPreviewDocument(data: pdfData, number: invoice.displayNumber)
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        } catch {
            onCopied(error.localizedDescription)
        }
    }

    var body: some View {
        Group {
            if isPad {
                ProformaTransactionDossier_iPad(
                    invoice: invoice,
                    statusKind: statusKind,
                    canWrite: session.hasPermission("pos.sell"),
                    onPrint: { makeLocalPreview() },
                    onWhatsApp: onWhatsApp,
                    onEdit: onEdit,
                    onConvert: onConvert,
                    onCancel: onCancel,
                    onViewReceipt: onViewReceipt,
                    onCopyServerID: {
                        UIPasteboard.general.string = invoice.id
                        onCopied(Language.get("Proforma_Copy_Success", alter: "تم نسخ معرّف الفاتورة إلى الحافظة"))
                    },
                    onDismiss: { dismiss() }
                )
            } else {
                ProformaTransactionDossier_iPhone(
                    invoice: invoice,
                    statusKind: statusKind,
                    canWrite: session.hasPermission("pos.sell"),
                    onPrint: { makeLocalPreview() },
                    onWhatsApp: onWhatsApp,
                    onEdit: onEdit,
                    onConvert: onConvert,
                    onCancel: onCancel,
                    onViewReceipt: onViewReceipt,
                    onCopyServerID: {
                        UIPasteboard.general.string = invoice.id
                        onCopied(Language.get("Proforma_Copy_Success", alter: "تم نسخ معرّف الفاتورة إلى الحافظة"))
                    },
                    onDismiss: { dismiss() }
                )
            }
        }
        .proformaPDFPresenter(previewDocument: $previewDocument, shareDocument: $shareDocument)
        .environment(\.layoutDirection, Language.isRTL() ? .rightToLeft : .leftToRight)
        .environment(\.locale, Locale(identifier: Language.isRTL() ? "ar_QA" : "en_US"))
    }
}

// MARK: - iPhone Cockpit Architecture

private struct ProformaTransactionDossier_iPhone: View {
    let invoice: ProformaInvoice
    let statusKind: ProformaDossierStatusKind
    let canWrite: Bool
    let onPrint: () -> Void
    let onWhatsApp: () -> Void
    let onEdit: () -> Void
    let onConvert: () -> Void
    let onCancel: () -> Void
    let onViewReceipt: () -> Void
    let onCopyServerID: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        ZStack {
            AdminSurface.background.ignoresSafeArea()

            // Atmospheric Glow
            VStack {
                LinearGradient(
                    colors: [statusKind.tintColor.opacity(0.12), Color.clear],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 220)
                .ignoresSafeArea()
                Spacer()
            }

            VStack(spacing: 0) {
                // Header Bar
                HStack(alignment: .center, spacing: 12) {
                    AdminSquircleCloseButton { onDismiss() }

                    VStack(alignment: .leading, spacing: 2) {
                        Text(Language.get("Proforma_Dossier_Title", alter: "ملف الفاتورة المبدئية"))
                            .font(DossierFont.bold(17, relativeTo: .headline))
                            .foregroundColor(AdminSurface.primaryText)

                        HStack(spacing: 6) {
                            Text(verbatim: invoice.displayNumber)
                                .font(DossierFont.bold(13, relativeTo: .caption))
                                .foregroundColor(Color(uiColor: .ppPrimary))
                                .environment(\.layoutDirection, .leftToRight)

                            if !invoice.branchName.isEmpty {
                                Text("•")
                                    .font(DossierFont.regular(12, relativeTo: .caption2))
                                    .foregroundColor(AdminSurface.secondaryText)
                                Text(invoice.branchName)
                                    .font(DossierFont.regular(12, relativeTo: .caption2))
                                    .foregroundColor(AdminSurface.secondaryText)
                            }
                        }
                    }

                    Spacer()

                    // Status Pill
                    HStack(spacing: 5) {
                        Image(systemName: statusKind.iconName)
                            .font(.system(size: 11, weight: .bold))
                        Text(statusKind.localizedTitle)
                            .font(DossierFont.bold(11, relativeTo: .caption2))
                    }
                    .foregroundColor(statusKind.tintColor)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(statusKind.tintColor.opacity(0.12), in: Capsule())
                    .overlay(Capsule().strokeBorder(statusKind.tintColor.opacity(0.3), lineWidth: 1))
                }
                .padding(.horizontal, AdminSpacing.screenMargin)
                .padding(.vertical, AdminSpacing.md)

                Divider().background(AdminSurface.hairline)

                // Scrollable Content
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: AdminSpacing.md) {
                        // Converted / Expired / Cancelled Banner
                        if invoice.status == .converted {
                            DossierConvertedBanner(
                                transactionID: invoice.convertedTransactionId,
                                onViewReceipt: onViewReceipt
                            )
                        } else if invoice.status == .cancelled {
                            DossierCancelledBanner()
                        } else if invoice.isExpired {
                            DossierExpiredBanner(validUntil: invoice.validUntil)
                        }

                        // Customer Conduit Card
                        DossierCustomerCard(
                            customerName: invoice.customer?.name ?? "",
                            customerPhone: invoice.customer?.phone ?? "",
                            isPreparingWhatsApp: false,
                            onCall: {
                                if let phone = invoice.customer?.phone, let url = URL(string: "tel://\(phone.filter("0123456789+".contains))") {
                                    UIApplication.shared.open(url)
                                }
                            },
                            onWhatsApp: onWhatsApp
                        )

                        // Itemized Manifest
                        DossierItemsManifestCard(
                            items: invoice.items,
                            currency: invoice.currency
                        )

                        // Commercial Terms & Validity Card
                        DossierTermsCard(invoice: invoice)

                        // Financial Ledger Card
                        DossierFinancialCard(invoice: invoice)

                        // Server Audit & Governance Card
                        DossierAuditCard(invoice: invoice, onCopyServerID: onCopyServerID)

                        Spacer().frame(height: 70)
                    }
                    .padding(AdminSpacing.screenMargin)
                }

                // Bottom Action Dock
                VStack(spacing: 10) {
                    Divider().background(AdminSurface.hairline)

                    HStack(spacing: 10) {
                        // Print / PDF Button
                        Button(action: onPrint) {
                            Image(systemName: "printer.fill")
                                .font(.system(size: 16, weight: .bold))
                                .foregroundColor(AdminSurface.primaryText)
                                .frame(width: 48, height: 48)
                                .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Color(uiColor: .ppSurfaceBorder), lineWidth: 1))
                        }
                        .buttonStyle(.plain)

                        // Convert Button (if issued)
                        if canWrite && invoice.status == .issued {
                            Button(action: onConvert) {
                                HStack(spacing: 6) {
                                    Image(systemName: "arrow.right.doc.on.clipboard")
                                        .font(.system(size: 14, weight: .bold))
                                    Text(Language.get("Proforma_Action_ConvertToSale", alter: "تحويل إلى بيع"))
                                        .font(DossierFont.bold(14, relativeTo: .subheadline))
                                }
                                .foregroundColor(Color.white)
                                .frame(maxWidth: .infinity)
                                .frame(height: 48)
                                .background(AdminSurface.emerald, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                            }
                            .buttonStyle(.plain)
                            .disabled(invoice.isExpired)
                        }

                        // Edit Button (if draft or issued)
                        if canWrite && (invoice.status == .draft || invoice.status == .issued) {
                            Button(action: onEdit) {
                                HStack(spacing: 6) {
                                    Image(systemName: "pencil")
                                        .font(.system(size: 14, weight: .bold))
                                    Text(Language.get("Proforma_Action_EditDraft", alter: "تعديل الفاتورة"))
                                        .font(DossierFont.bold(13, relativeTo: .subheadline))
                                }
                                .foregroundColor(AdminSurface.primary)
                                .frame(maxWidth: .infinity)
                                .frame(height: 48)
                                .background(AdminSurface.primary.opacity(0.1), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                            }
                            .buttonStyle(.plain)
                        }

                        // Cancel Button
                        if canWrite && (invoice.status == .draft || invoice.status == .issued) {
                            Button(action: onCancel) {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: 16, weight: .bold))
                                    .foregroundColor(Color(uiColor: .systemRed))
                                    .frame(width: 48, height: 48)
                                    .background(Color(uiColor: .systemRed).opacity(0.1), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, AdminSpacing.screenMargin)
                    .padding(.bottom, 12)
                }
                .background(AdminSurface.surface)
            }
        }
    }
}

// MARK: - iPad Dual-Wing Studio Console Architecture

private struct ProformaTransactionDossier_iPad: View {
    let invoice: ProformaInvoice
    let statusKind: ProformaDossierStatusKind
    let canWrite: Bool
    let onPrint: () -> Void
    let onWhatsApp: () -> Void
    let onEdit: () -> Void
    let onConvert: () -> Void
    let onCancel: () -> Void
    let onViewReceipt: () -> Void
    let onCopyServerID: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        ZStack {
            AdminSurface.background.ignoresSafeArea()

            VStack {
                LinearGradient(
                    colors: [statusKind.tintColor.opacity(0.14), Color.clear],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 260)
                .ignoresSafeArea()
                Spacer()
            }

            VStack(spacing: 0) {
                // Cockpit Header
                HStack(alignment: .center, spacing: 16) {
                    AdminSquircleCloseButton { onDismiss() }
                        .keyboardShortcut(.escape, modifiers: [])

                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 10) {
                            Text(Language.get("Proforma_Dossier_Title", alter: "ملف الفاتورة المبدئية"))
                                .font(DossierFont.bold(22, relativeTo: .title2))
                                .foregroundColor(AdminSurface.primaryText)

                            HStack(spacing: 6) {
                                Image(systemName: statusKind.iconName)
                                    .font(.system(size: 12, weight: .bold))
                                Text(statusKind.localizedTitle)
                                    .font(DossierFont.bold(12, relativeTo: .caption))
                            }
                            .foregroundColor(statusKind.tintColor)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(statusKind.tintColor.opacity(0.12), in: Capsule())
                            .overlay(Capsule().strokeBorder(statusKind.tintColor.opacity(0.3), lineWidth: 1))
                        }

                        HStack(spacing: 8) {
                            Text(verbatim: invoice.displayNumber)
                                .font(DossierFont.bold(14, relativeTo: .subheadline))
                                .foregroundColor(Color(uiColor: .ppPrimary))
                                .environment(\.layoutDirection, .leftToRight)

                            if !invoice.branchName.isEmpty {
                                Text("•")
                                    .font(DossierFont.regular(13, relativeTo: .caption))
                                    .foregroundColor(AdminSurface.secondaryText)
                                Text(invoice.branchName)
                                    .font(DossierFont.medium(13, relativeTo: .caption))
                                    .foregroundColor(AdminSurface.secondaryText)
                            }
                        }
                    }

                    Spacer()

                    // Quick Print Button
                    Button(action: onPrint) {
                        HStack(spacing: 8) {
                            Image(systemName: "printer.fill")
                                .font(.system(size: 14, weight: .bold))
                            Text(Language.get("POS_Dossier_PrintShortcutHint", alter: "طباعة (⌘P)"))
                                .font(DossierFont.bold(13, relativeTo: .subheadline))
                        }
                        .foregroundColor(AdminSurface.primaryText)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color(uiColor: .ppSurfaceBorder), lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    .keyboardShortcut("p", modifiers: .command)
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 18)

                Divider().background(AdminSurface.hairline)

                // Dual-Wing Console
                GeometryReader { geo in
                    let leadingWidth = max(360, geo.size.width * 0.40)

                    HStack(alignment: .top, spacing: 20) {
                        // Leading Wing: Financials, Customer & Commands (40%)
                        ScrollView(.vertical, showsIndicators: false) {
                            VStack(spacing: 16) {
                                DossierFinancialCard(invoice: invoice)

                                DossierCustomerCard(
                                    customerName: invoice.customer?.name ?? "",
                                    customerPhone: invoice.customer?.phone ?? "",
                                    isPreparingWhatsApp: false,
                                    onCall: {
                                        if let phone = invoice.customer?.phone, let url = URL(string: "tel://\(phone.filter("0123456789+".contains))") {
                                            UIApplication.shared.open(url)
                                        }
                                    },
                                    onWhatsApp: onWhatsApp
                                )

                                DossierTermsCard(invoice: invoice)

                                // Action Command Horizon
                                VStack(spacing: 10) {
                                    if canWrite && invoice.status == .issued {
                                        Button(action: onConvert) {
                                            HStack(spacing: 8) {
                                                Image(systemName: "arrow.right.doc.on.clipboard")
                                                    .font(.system(size: 15, weight: .bold))
                                                Text(Language.get("Proforma_Action_ConvertToSale", alter: "تحويل إلى بيع"))
                                                    .font(DossierFont.bold(15, relativeTo: .body))
                                            }
                                            .foregroundColor(.white)
                                            .frame(maxWidth: .infinity)
                                            .frame(height: 50)
                                            .background(AdminSurface.emerald, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                                        }
                                        .buttonStyle(.plain)
                                        .disabled(invoice.isExpired)
                                    }

                                    if canWrite && (invoice.status == .draft || invoice.status == .issued) {
                                        Button(action: onEdit) {
                                            HStack(spacing: 8) {
                                                Image(systemName: "pencil")
                                                    .font(.system(size: 15, weight: .bold))
                                                Text(Language.get("Proforma_Action_EditDraft", alter: "تعديل الفاتورة"))
                                                    .font(DossierFont.bold(14, relativeTo: .body))
                                            }
                                            .foregroundColor(AdminSurface.primary)
                                            .frame(maxWidth: .infinity)
                                            .frame(height: 50)
                                            .background(AdminSurface.primary.opacity(0.1), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                                        }
                                        .buttonStyle(.plain)
                                    }

                                    if canWrite && (invoice.status == .draft || invoice.status == .issued) {
                                        Button(action: onCancel) {
                                            HStack(spacing: 8) {
                                                Image(systemName: "xmark.circle.fill")
                                                    .font(.system(size: 15, weight: .bold))
                                                Text(Language.get("Proforma_CancelInvoice", alter: "إلغاء الفاتورة"))
                                                    .font(DossierFont.bold(14, relativeTo: .body))
                                            }
                                            .foregroundColor(Color(uiColor: .systemRed))
                                            .frame(maxWidth: .infinity)
                                            .frame(height: 50)
                                            .background(Color(uiColor: .systemRed).opacity(0.1), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                            }
                            .padding(20)
                        }
                        .frame(width: leadingWidth)
                        .background(AdminSurface.surface)

                        // Trailing Wing: Manifest & Governance (60%)
                        ScrollView(.vertical, showsIndicators: false) {
                            VStack(spacing: 16) {
                                if invoice.status == .converted {
                                    DossierConvertedBanner(
                                        transactionID: invoice.convertedTransactionId,
                                        onViewReceipt: onViewReceipt
                                    )
                                } else if invoice.status == .cancelled {
                                    DossierCancelledBanner()
                                } else if invoice.isExpired {
                                    DossierExpiredBanner(validUntil: invoice.validUntil)
                                }

                                DossierItemsManifestCard(
                                    items: invoice.items,
                                    currency: invoice.currency
                                )

                                DossierAuditCard(invoice: invoice, onCopyServerID: onCopyServerID)
                            }
                            .padding(24)
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
            }
        }
    }
}

// MARK: - Dossier Modular Cards

private struct DossierConvertedBanner: View {
    let transactionID: String?
    let onViewReceipt: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 26))
                .foregroundColor(AdminSurface.emerald)

            VStack(alignment: .leading, spacing: 2) {
                Text(Language.get("Proforma_Converted_Title", alter: "حُوّلت إلى عملية بيع مكتملة"))
                    .font(DossierFont.bold(15, relativeTo: .headline))
                    .foregroundColor(AdminSurface.emerald)
                if let tx = transactionID {
                    Text(verbatim: "\(Language.get("POS_TransactionID", alter: "رقم الإيصال")): \(POSReceiptFormat.receiptID(tx))")
                        .font(DossierFont.medium(12, relativeTo: .caption))
                        .foregroundColor(AdminSurface.secondaryText)
                }
            }

            Spacer()

            Button(action: onViewReceipt) {
                Text(Language.get("Proforma_ViewSale", alter: "عرض الإيصال"))
                    .font(DossierFont.bold(13, relativeTo: .subheadline))
                    .foregroundColor(Color.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(AdminSurface.emerald, in: Capsule())
            }
            .buttonStyle(.plain)
        }
        .padding(14)
        .background(AdminSurface.emerald.opacity(0.1), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

private struct DossierExpiredBanner: View {
    let validUntil: String?

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "clock.badge.xmark.fill")
                .font(.system(size: 24))
                .foregroundColor(AdminSurface.danger)
            VStack(alignment: .leading, spacing: 2) {
                Text(Language.get("Proforma_Status_expired", alter: "منتهية الصلاحية"))
                    .font(DossierFont.bold(14, relativeTo: .headline))
                    .foregroundColor(AdminSurface.danger)
                if let valid = validUntil {
                    Text(String(format: Language.get("Proforma_ExpiredOn", alter: "انتهت في %@"), valid))
                        .font(DossierFont.regular(12, relativeTo: .caption))
                        .foregroundColor(AdminSurface.secondaryText)
                }
            }
            Spacer()
        }
        .padding(14)
        .background(AdminSurface.danger.opacity(0.08), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

private struct DossierCancelledBanner: View {
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "xmark.octagon.fill")
                .font(.system(size: 24))
                .foregroundColor(AdminSurface.danger)
            VStack(alignment: .leading, spacing: 2) {
                Text(Language.get("Proforma_Status_cancelled", alter: "ملغاة"))
                    .font(DossierFont.bold(14, relativeTo: .headline))
                    .foregroundColor(AdminSurface.danger)
                Text(Language.get("Proforma_Cancelled_Hint", alter: "تم إبطال هذه الفاتورة المبدئية ولا يمكن تحويلها إلى بيع."))
                    .font(DossierFont.regular(12, relativeTo: .caption))
                    .foregroundColor(AdminSurface.secondaryText)
            }
            Spacer()
        }
        .padding(14)
        .background(AdminSurface.danger.opacity(0.08), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

private struct DossierCustomerCard: View {
    let customerName: String
    let customerPhone: String
    let isPreparingWhatsApp: Bool
    let onCall: () -> Void
    let onWhatsApp: () -> Void

    private var isWalkIn: Bool {
        customerName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        customerPhone.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(Language.get("Proforma_Dossier_Customer_Section", alter: "بيانات العميل"))
                .font(DossierFont.bold(13, relativeTo: .caption))
                .foregroundColor(AdminSurface.secondaryText)

            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(isWalkIn ? Color(uiColor: .ppBackgroundSecondary) : Color(uiColor: .ppPrimary).opacity(0.12))
                        .frame(width: 44, height: 44)

                    Image(systemName: isWalkIn ? "person.fill" : "person.crop.circle.fill")
                        .font(.system(size: 22))
                        .foregroundColor(isWalkIn ? AdminSurface.secondaryText : Color(uiColor: .ppPrimary))
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(isWalkIn ? Language.get("POS_Dossier_WalkInCustomer", alter: "عميل نقدي مباشر / لم يُحدد") : customerName)
                        .font(DossierFont.bold(15, relativeTo: .body))
                        .foregroundColor(AdminSurface.primaryText)

                    if !customerPhone.isEmpty {
                        Text(verbatim: customerPhone)
                            .font(DossierFont.medium(13, relativeTo: .caption))
                            .foregroundColor(AdminSurface.secondaryText)
                            .environment(\.layoutDirection, .leftToRight)
                    }
                }

                Spacer()

                if !customerPhone.isEmpty {
                    HStack(spacing: 8) {
                        Button(action: onCall) {
                            ZStack {
                                Circle()
                                    .fill(Color(uiColor: .systemBlue))
                                    .frame(width: 36, height: 36)
                                Image(systemName: "phone.fill")
                                    .font(.system(size: 14, weight: .bold))
                                    .foregroundColor(.white)
                            }
                        }
                        .buttonStyle(.plain)

                        Button(action: onWhatsApp) {
                            ZStack {
                                Circle()
                                    .fill(ProformaWhatsAppSender.brandColor)
                                    .frame(width: 36, height: 36)
                                Image("whatsapp")
                                    .renderingMode(.template)
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: 18, height: 18)
                                    .foregroundColor(.white)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(14)
        .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color(uiColor: .ppSurfaceBorder).opacity(0.8), lineWidth: 0.8)
        )
    }
}

private struct DossierItemsManifestCard: View {
    let items: [ProformaLine]
    let currency: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(Language.get("Proforma_Dossier_Items_Section", alter: "العناصر المدرجة"))
                    .font(DossierFont.bold(13, relativeTo: .caption))
                    .foregroundColor(AdminSurface.secondaryText)

                Spacer()

                Text(String(format: Language.get("POS_Dossier_ItemsCount", alter: "%d عنصر"), items.count))
                    .font(DossierFont.medium(12, relativeTo: .caption2))
                    .foregroundColor(AdminSurface.secondaryText)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(Color(uiColor: .ppBackgroundSecondary), in: Capsule())
            }

            VStack(spacing: 0) {
                ForEach(0..<items.count, id: \.self) { idx in
                    let item = items[idx]
                    DossierLineItemRow(item: item, currency: currency, isLast: idx == items.count - 1)
                }
            }
            .padding(14)
            .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(Color(uiColor: .ppSurfaceBorder).opacity(0.8), lineWidth: 0.8)
            )
        }
    }
}

private struct DossierLineItemRow: View {
    let item: ProformaLine
    let currency: String
    let isLast: Bool

    var body: some View {
        VStack(spacing: 8) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.name.isEmpty ? Language.get("Proforma_UnnamedProduct", alter: "عنصر") : item.name)
                        .font(DossierFont.bold(15, relativeTo: .body))
                        .foregroundColor(AdminSurface.primaryText)
                        .fixedSize(horizontal: false, vertical: true)

                    HStack(spacing: 6) {
                        Text(verbatim: "\(item.quantity) × \(POSReceiptFormat.currency(proformaDoublePrice(item.unitPrice), code: currency))")
                            .font(DossierFont.medium(12, relativeTo: .caption))
                            .foregroundColor(AdminSurface.secondaryText)

                        if item.lineDiscountMinor > 0 {
                            Text(verbatim: "−\(POSReceiptFormat.currency(Double(item.lineDiscountMinor) / 100.0, code: currency))")
                                .font(DossierFont.bold(10, relativeTo: .caption2))
                                .foregroundColor(Color(uiColor: .systemGreen))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color(uiColor: .systemGreen).opacity(0.12), in: Capsule())
                        }
                    }

                    if !item.unitIds.isEmpty {
                        Text(String(format: pf("Proforma_ExactUnits"), item.unitIds.count))
                            .font(DossierFont.bold(11, relativeTo: .caption2))
                            .foregroundColor(AdminSurface.primary)
                    }
                }

                Spacer()

                Text(verbatim: POSReceiptFormat.currency(Double(item.totalMinor) / 100.0, code: currency))
                    .font(DossierFont.bold(15, relativeTo: .subheadline))
                    .foregroundColor(AdminSurface.primaryText)
                    .monospacedDigit()
            }

            if !isLast {
                Divider().background(AdminSurface.hairline)
            }
        }
        .padding(.vertical, 4)
    }
}

private struct DossierTermsCard: View {
    let invoice: ProformaInvoice

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(Language.get("Proforma_Dossier_Terms_Section", alter: "شروط وصلاحية العرض"))
                .font(DossierFont.bold(13, relativeTo: .caption))
                .foregroundColor(AdminSurface.secondaryText)

            VStack(spacing: 8) {
                if let valid = invoice.validUntil, !valid.isEmpty {
                    dossierRow(
                        label: Language.get("Proforma_ValidUntil", alter: "صالحة حتى"),
                        value: valid,
                        valueColor: invoice.isExpired ? AdminSurface.danger : AdminSurface.primaryText
                    )
                }
                if let issued = invoice.issuedAt {
                    dossierRow(
                        label: Language.get("Proforma_IssuedAt", alter: "تاريخ الإصدار"),
                        value: issued.formatted(date: .abbreviated, time: .shortened)
                    )
                }
                if !invoice.notes.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(Language.get("Proforma_Notes", alter: "الملاحظات"))
                            .font(DossierFont.medium(12, relativeTo: .caption))
                            .foregroundColor(AdminSurface.secondaryText)
                        Text(invoice.notes)
                            .font(DossierFont.regular(13, relativeTo: .body))
                            .foregroundColor(AdminSurface.primaryText)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(14)
            .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Color(uiColor: .ppSurfaceBorder).opacity(0.8), lineWidth: 0.8))
        }
    }

    private func dossierRow(label: String, value: String, valueColor: Color = AdminSurface.primaryText) -> some View {
        HStack {
            Text(label)
                .font(DossierFont.medium(14, relativeTo: .body))
                .foregroundColor(AdminSurface.secondaryText)
            Spacer()
            Text(verbatim: value)
                .font(DossierFont.bold(14, relativeTo: .body))
                .foregroundColor(valueColor)
        }
    }
}

private struct DossierFinancialCard: View {
    let invoice: ProformaInvoice

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(Language.get("Proforma_Dossier_Financial_Section", alter: "التفاصيل المالية"))
                .font(DossierFont.bold(13, relativeTo: .caption))
                .foregroundColor(AdminSurface.secondaryText)

            VStack(spacing: 9) {
                dossierRow(
                    label: Language.get("Proforma_Subtotal", alter: "المجموع الفرعي"),
                    value: POSReceiptFormat.currency(Double(invoice.totals.subtotalMinor) / 100.0, code: invoice.currency)
                )

                let totalDiscount = invoice.totals.lineDiscountMinor + invoice.totals.discountMinor
                if totalDiscount > 0 {
                    dossierRow(
                        label: Language.get("Proforma_Discount", alter: "الخصومات"),
                        value: "−" + POSReceiptFormat.currency(Double(totalDiscount) / 100.0, code: invoice.currency),
                        valueColor: Color(uiColor: .systemGreen)
                    )
                }

                if invoice.totals.taxMinor > 0 {
                    dossierRow(
                        label: Language.get("Proforma_Tax", alter: "الضريبة"),
                        value: POSReceiptFormat.currency(Double(invoice.totals.taxMinor) / 100.0, code: invoice.currency)
                    )
                }

                Divider().background(AdminSurface.hairline)

                HStack(alignment: .center) {
                    Text(Language.get("Proforma_Total", alter: "الإجمالي المقترح"))
                        .font(DossierFont.bold(15, relativeTo: .headline))
                        .foregroundColor(AdminSurface.primaryText)

                    Spacer()

                    Text(verbatim: POSReceiptFormat.currency(Double(invoice.totals.totalMinor) / 100.0, code: invoice.currency))
                        .font(DossierFont.bold(22, relativeTo: .title2))
                        .foregroundColor(AdminSurface.emerald)
                        .monospacedDigit()
                }
                .padding(.top, 2)
            }
            .padding(14)
            .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Color(uiColor: .ppSurfaceBorder).opacity(0.8), lineWidth: 0.8))
        }
    }

    private func dossierRow(label: String, value: String, valueColor: Color = AdminSurface.primaryText) -> some View {
        HStack {
            Text(label)
                .font(DossierFont.medium(14, relativeTo: .body))
                .foregroundColor(AdminSurface.secondaryText)
            Spacer()
            Text(verbatim: value)
                .font(DossierFont.bold(14, relativeTo: .body))
                .foregroundColor(valueColor)
                .monospacedDigit()
        }
    }
}

private struct DossierAuditCard: View {
    let invoice: ProformaInvoice
    let onCopyServerID: () -> Void

    var body: some View {
        VStack(spacing: 9) {
            HStack {
                Text(Language.get("Proforma_Created", alter: "وقت الإنشاء"))
                    .font(DossierFont.medium(12, relativeTo: .caption))
                    .foregroundColor(AdminSurface.secondaryText)
                Spacer()
                Text(invoice.createdAt.formatted(date: .abbreviated, time: .shortened))
                    .font(DossierFont.bold(12, relativeTo: .caption))
                    .foregroundColor(AdminSurface.primaryText)
            }

            HStack {
                Text(Language.get("Proforma_Version", alter: "النسخة"))
                    .font(DossierFont.medium(12, relativeTo: .caption))
                    .foregroundColor(AdminSurface.secondaryText)
                Spacer()
                Text("v\(invoice.version)")
                    .font(DossierFont.bold(12, relativeTo: .caption))
                    .foregroundColor(AdminSurface.primaryText)
            }

            HStack {
                Text(Language.get("Proforma_Dossier_ServerID", alter: "معرّف الفاتورة"))
                    .font(DossierFont.medium(12, relativeTo: .caption))
                    .foregroundColor(AdminSurface.secondaryText)
                Spacer()
                Button(action: onCopyServerID) {
                    HStack(spacing: 5) {
                        Text(verbatim: String(invoice.id.prefix(16)) + "...")
                            .font(DossierFont.bold(11, relativeTo: .caption2))
                            .foregroundColor(Color(uiColor: .ppPrimary))
                        Image(systemName: "doc.on.doc")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(AdminSurface.secondaryText)
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(Color(uiColor: .ppPrimary).opacity(0.08), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(14)
        .background(Color(uiColor: .ppBackgroundSecondary).opacity(0.5), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

// MARK: - Proforma Studio Editor Sheet (Dedicated Full-Screen Modal)

struct ProformaEditorStudioSheet: View {
    let session: AdminSession
    @ObservedObject var store: ProformaInvoiceStore
    @ObservedObject var kindsProvider: ProformaMainKindsProvider
    let activeBranchID: String
    let canWrite: Bool

    let onClose: () -> Void
    let onPreview: (ProformaInvoice) -> Void
    let onConvert: (ProformaInvoice) -> Void
    let onCancelInvoice: (ProformaInvoice) -> Void
    let onToast: (String) -> Void

    @State private var customerPicker = false
    @State private var catalogPicker = false
    @State private var previewDocument: ProformaPreviewDocument? = nil
    @State private var shareDocument: PPProformaPDFDocument? = nil

    private var editable: Bool {
        canWrite && !store.isLocked && !store.isLoading && (store.selected?.status.isEditable ?? true)
    }

    private func makeLocalPreview() {
        guard !store.isLocked else { return }
        if let sel = store.selected {
            do {
                let snapshot = try ProformaWhatsAppSender.makeSnapshot(for: sel)
                let pdfData = try PPProformaPDFRenderer.render(snapshot: snapshot)
                previewDocument = ProformaPreviewDocument(data: pdfData, number: sel.displayNumber)
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            } catch {
                onToast(error.localizedDescription)
            }
        } else if let draft = store.draft {
            do {
                let snapshot = try ProformaWhatsAppSender.makeSnapshot(for: draft)
                let pdfData = try PPProformaPDFRenderer.render(snapshot: snapshot)
                previewDocument = ProformaPreviewDocument(data: pdfData, number: draft.displayNumber ?? Language.get("Proforma_NewDraft", alter: "مسودة جديدة"))
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            } catch {
                onToast(error.localizedDescription)
            }
        }
    }

    var body: some View {
        ZStack {
            AdminSurface.background.ignoresSafeArea()

            VStack(spacing: 0) {
                // Header
                HStack(spacing: 12) {
                    AdminSquircleCloseButton {
                        if store.hasUnsavedChanges {
                            promptDiscardConfirmation()
                        } else {
                            onClose()
                        }
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text(store.draft?.displayNumber ?? Language.get("Proforma_NewDraft", alter: "مسودة جديدة"))
                            .font(PPBeirutiFont.bold(20, relativeTo: .title3))
                            .foregroundStyle(AdminSurface.primaryText)
                            .lineLimit(1)
                            .environment(\.layoutDirection, store.draft?.number != nil ? .leftToRight : (Language.isRTL() ? .rightToLeft : .leftToRight))

                        Text(Language.get("Proforma_DocumentLabel", alter: "فاتورة مبدئية · ليست إيصال بيع"))
                            .font(AdminType.caption)
                            .foregroundStyle(AdminSurface.secondaryText)
                    }

                    Spacer()

                    if store.hasUnsavedChanges {
                        HStack(spacing: 4) {
                            Circle().fill(AdminSurface.amber).frame(width: 7, height: 7)
                            Text(Language.get("Proforma_Unsaved", alter: "لم تُحفظ"))
                                .font(AdminType.captionBold)
                                .foregroundStyle(AdminSurface.amber)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(AdminSurface.amber.opacity(0.12), in: Capsule())
                    }
                }
                .padding(.horizontal, AdminSpacing.screenMargin)
                .padding(.vertical, AdminSpacing.md)
                .background(AdminSurface.surface)

                Divider().background(AdminSurface.hairline)

                // Body
                if let draft = store.draft {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 18) {
                            if store.confirmationPending {
                                ProformaConfirmationPendingBanner(onRetry: { Task { await store.retryConfirmation() } })
                            }

                            if let err = store.error {
                                ProformaErrorBanner(
                                    message: err,
                                    canRetry: store.canRetryMutation,
                                    isConflict: store.errorIsConflict,
                                    onRetry: { Task { await store.retryMutation() } },
                                    onReload: { Task { await store.reloadSelection() } }
                                )
                            }

                            // Customer Card
                            ProformaCustomerStudioCard(
                                customer: draft.customer,
                                editable: editable,
                                onSelect: { customerPicker = true },
                                onRemove: { store.draft?.customer = nil }
                            )

                            // Line Items Workbench
                            ProformaLineItemsStudio(
                                items: bindingForItems(),
                                currency: draft.currency,
                                editable: editable,
                                onAddItem: { catalogPicker = true },
                                onRemoveItem: { item in
                                    store.draft?.items.removeAll(where: { $0.id == item.id })
                                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                                }
                            )

                            // Terms & Validity Presets
                            ProformaTermsStudioCard(
                                draft: bindingForDraft(),
                                editable: editable
                            )

                            // Financial Summary
                            ProformaFinancialSummaryCard(
                                draft: draft,
                                selected: store.selected,
                                hasUnsaved: store.hasUnsavedChanges
                            )

                            Text(Language.get("Proforma_Disclosure", alter: "هذه فاتورة مبدئية وليست إثباتاً للدفع."))
                                .font(AdminType.caption)
                                .foregroundStyle(AdminSurface.secondaryText)
                                .padding(.top, 4)

                            Spacer().frame(height: 80)
                        }
                        .padding(AdminSpacing.screenMargin)
                    }
                    .scrollDismissesKeyboard(.interactively)
                    .safeAreaInset(edge: .bottom) {
                        ProformaCommandDock(
                            store: store,
                            editable: editable,
                            canWrite: canWrite,
                            onSave: {
                                Task {
                                    await store.perform("save")
                                    onToast(Language.get("Proforma_Save_Success", alter: "تم حفظ المسودة بنجاح"))
                                }
                            },
                            onIssue: {
                                Task {
                                    await store.perform("issue")
                                    onToast(Language.get("Proforma_Issue_Success", alter: "تم إصدار الفاتورة المبدئية"))
                                }
                            },
                            onConvert: {
                                if let sel = store.selected { onConvert(sel) }
                            },
                            onPreview: {
                                makeLocalPreview()
                            },
                            onCancel: {
                                if let sel = store.selected { onCancelInvoice(sel) }
                            }
                        )
                    }
                } else {
                    ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .environment(\.layoutDirection, Language.isRTL() ? .rightToLeft : .leftToRight)
        .sheet(isPresented: $customerPicker) {
            POSCustomerPickerSheet(
                currentSelected: store.draft?.customer?.pickerRecord,
                canCreateCustomer: canWrite,
                purpose: .proformaInvoice
            ) { record in
                store.draft?.customer = ProformaCustomer(record)
                customerPicker = false
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            }
        }
        .fullScreenCover(isPresented: $catalogPicker) {
            ProformaCatalogSheet(
                store: store,
                kindsProvider: kindsProvider,
                currency: store.draft?.currency ?? "QAR"
            )
        }
        .proformaPDFPresenter(previewDocument: $previewDocument, shareDocument: $shareDocument)
    }

    private func promptDiscardConfirmation() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        PPAlertHelper.showDestructiveConfirmation(
            in: nil,
            title: Language.get("Proforma_Discard_Title", alter: "تجاهل التغييرات؟"),
            subtitle: Language.get("Proforma_Discard_Message", alter: "تبقى الفاتورة المحفوظة كما هي وستفقد أي تعديلات لم تُحفظ."),
            confirmButton: Language.get("Proforma_Discard", alter: "تجاهل التغييرات"),
            cancelButton: Language.get("Proforma_KeepEditing", alter: "متابعة التعديل"),
            icon: UIImage(systemName: "trash.fill"),
            confirmBlock: { _, didConfirm in
                guard didConfirm else { return }
                store.clearSelection()
                onClose()
            },
            cancelBlock: nil
        )
    }

    private func bindingForDraft() -> Binding<ProformaDraft> {
        Binding(
            get: { store.draft ?? ProformaDraft(branchId: activeBranchID, currency: "QAR") },
            set: { store.draft = $0 }
        )
    }

    private func bindingForItems() -> Binding<[ProformaLine]> {
        Binding(
            get: { store.draft?.items ?? [] },
            set: { store.draft?.items = $0 }
        )
    }
}

// MARK: - Category-Defining Horizontal MainKinds Rail & Catalog Sheet

struct ProformaCatalogSheet: View {
    @ObservedObject var store: ProformaInvoiceStore
    @ObservedObject var kindsProvider: ProformaMainKindsProvider
    let currency: String

    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var selectedKindID: Int? = nil

    private var filteredCatalog: [ProformaCatalogItem] {
        var items = store.catalog
        if let kindID = selectedKindID, let kind = kindsProvider.kinds.first(where: { $0.id == kindID }) {
            let kAr = kind.nameAr.lowercased()
            let kEn = kind.nameEn.lowercased()
            items = items.filter { item in
                let n = item.name.lowercased()
                return n.contains(kAr) || (!kEn.isEmpty && n.contains(kEn)) || item.groupName.lowercased().contains(kAr)
            }
        }
        return items
    }

    var body: some View {
        ZStack {
            AdminSurface.background.ignoresSafeArea()

            VStack(spacing: 0) {
                // MARK: - Studio Navigation Header & Controls
                VStack(spacing: 0) {
                    HStack(spacing: 12) {
                        AdminSquircleCloseButton {
                            dismiss()
                        }

                        VStack(alignment: .leading, spacing: 2) {
                            Text(Language.get("Proforma_AddItem", alter: "إضافة منتج"))
                                .font(PPBeirutiFont.bold(20, relativeTo: .title3))
                                .foregroundStyle(AdminSurface.primaryText)

                            Text(Language.get("Proforma_Catalog_Subtitle", alter: "اختر المنتجات والعبوات المناسبة للفاتورة"))
                                .font(AdminType.caption)
                                .foregroundStyle(AdminSurface.secondaryText)
                        }

                        Spacer()

                        if let draft = store.draft, !draft.items.isEmpty {
                            HStack(spacing: 6) {
                                Image(systemName: "cart.fill")
                                    .font(.system(size: 11, weight: .bold))
                                Text("\(draft.items.count)")
                                    .font(AdminType.captionBold)
                            }
                            .foregroundStyle(AdminSurface.primary)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(AdminSurface.primarySoft, in: Capsule())
                        }
                    }
                    .padding(.horizontal, AdminSpacing.screenMargin)
                    .padding(.top, 10)
                    .padding(.bottom, 10)

                    // Search & Barcode Scan Bar
                    HStack(spacing: 10) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(AdminSurface.secondaryText)

                        TextField(Language.get("Proforma_CatalogSearch", alter: "الاسم أو رمز المنتج أو الباركود"), text: $query)
                            .font(AdminType.body)
                            .submitLabel(.search)

                        if !query.isEmpty {
                            Button {
                                query = ""
                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: 16))
                                    .foregroundStyle(AdminSurface.secondaryText)
                            }
                        }

                        AdminBarcodeScanButton(isCircle: false) { scannedCode in
                            let cleaned = scannedCode.trimmingCharacters(in: .whitespacesAndNewlines)
                            guard !cleaned.isEmpty else { return }
                            query = cleaned
                            Task {
                                await store.searchCatalog(cleaned)
                            }
                        }
                    }
                    .padding(.horizontal, 12)
                    .frame(height: 50)
                    .background(AdminSurface.backgroundSecondary, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(AdminSurface.hairline, lineWidth: 1)
                    )
                    .padding(.horizontal, AdminSpacing.screenMargin)
                    .padding(.top, 4)
                    .padding(.bottom, 10)

                    ProformaMainKindsRail(
                        kinds: kindsProvider.kinds,
                        selectedKindID: $selectedKindID
                    )
                    .padding(.bottom, 8)

                    Divider().background(AdminSurface.hairline)
                }
                .background(
                    AdminSurface.surface
                        .ignoresSafeArea(edges: .top)
                )

                ScrollView {
                    if store.catalogLoading && store.catalog.isEmpty {
                        ProformaCatalogGridShimmer(columns: catalogGridColumns, tileHeight: tileHeight)
                            .padding(.horizontal, 12)
                            .padding(.top, 12)
                            .padding(.bottom, 24)
                    } else if let error = store.catalogError {
                        ProformaErrorBanner(
                            message: error,
                            canRetry: true,
                            isConflict: false,
                            onRetry: { Task { await store.searchCatalog(query) } },
                            onReload: {}
                        )
                        .padding(.top, 16)
                        .padding(.horizontal, 16)
                    } else if filteredCatalog.isEmpty {
                        ProformaEmptyStateView(
                            title: "Proforma_CatalogEmpty",
                            detail: "Proforma_Empty_Search_Detail",
                            systemImage: "tray"
                        )
                        .padding(.vertical, 40)
                    } else {
                        LazyVGrid(columns: catalogGridColumns, spacing: 8) {
                            ForEach(filteredCatalog) { item in
                                ProformaCatalogTile(
                                    item: item,
                                    inDraft: currentQuantityInDraftInt(item),
                                    currency: currency,
                                    tileHeight: tileHeight,
                                    onTap: {
                                        store.add(item)
                                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                                    },
                                    onIncrement: { incrementDraftItem(item) },
                                    onDecrement: { decrementDraftItem(item) }
                                )
                            }
                        }
                        .padding(.horizontal, 12)
                        .padding(.top, 12)
                        .padding(.bottom, 16)

                        if store.catalogCursor != nil {
                            Button(Language.get("Proforma_LoadMore", alter: "تحميل المزيد")) {
                                Task { await store.searchCatalog(query, append: true) }
                            }
                            .font(AdminType.bodyBold)
                            .frame(maxWidth: .infinity, minHeight: 44)
                            .disabled(store.catalogLoading)
                            .padding(.horizontal, 16)
                            .padding(.bottom, 24)

                            if store.catalogLoading { ProgressView().padding(.bottom, 16) }
                        }
                    }
                }
            }
        }
        .environment(\.layoutDirection, Language.isRTL() ? .rightToLeft : .leftToRight)
        .task(id: query) {
            do { try await Task.sleep(for: .milliseconds(query.isEmpty ? 0 : 250)) } catch { return }
            guard !Task.isCancelled else { return }
            await store.searchCatalog(query)
        }
    }

    private var catalogGridColumns: [GridItem] {
        if UIDevice.current.userInterfaceIdiom == .pad {
            return Array(repeating: GridItem(.flexible(), spacing: 8), count: 5)
        } else {
            return [
                GridItem(.flexible(), spacing: 8),
                GridItem(.flexible(), spacing: 8),
                GridItem(.flexible(), spacing: 8)
            ]
        }
    }

    private var tileHeight: CGFloat {
        UIDevice.current.userInterfaceIdiom == .pad ? 160 : 134
    }

    private func currentQuantityInDraftInt(_ item: ProformaCatalogItem) -> Int {
        guard let line = store.draft?.items.first(where: { $0.productId == item.productId && $0.quantityGroupId == item.quantityGroupId }),
              let dec = ProformaDecimal.parse(line.quantity, scale: 3) else {
            return 0
        }
        return NSDecimalNumber(decimal: dec).intValue
    }

    private func currentQuantityInDraft(_ item: ProformaCatalogItem) -> Decimal? {
        guard let line = store.draft?.items.first(where: { $0.productId == item.productId && $0.quantityGroupId == item.quantityGroupId }) else {
            return nil
        }
        return ProformaDecimal.parse(line.quantity, scale: 3)
    }

    private func incrementDraftItem(_ item: ProformaCatalogItem) {
        store.add(item)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    private func decrementDraftItem(_ item: ProformaCatalogItem) {
        guard var draft = store.draft,
              let idx = draft.items.firstIndex(where: { $0.productId == item.productId && $0.quantityGroupId == item.quantityGroupId }) else { return }
        let current = ProformaDecimal.parse(draft.items[idx].quantity, scale: 3) ?? 0
        if current <= 1 {
            draft.items.remove(at: idx)
        } else {
            draft.items[idx].quantity = ProformaDecimal.string(current - 1)
        }
        store.draft = draft
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }
}

// MARK: - Reinvented MainKinds Rail & Lens Items

struct ProformaMainKindsRail: View {
    let kinds: [PFMainKindItem]
    @Binding var selectedKindID: Int?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                MainKindCapsule(
                    title: Language.get("Proforma_Filter_Species_All", alter: "الكل"),
                    systemImage: "sparkles",
                    imageUrl: nil,
                    themeColor: AdminSurface.primary,
                    isSelected: selectedKindID == nil
                ) {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    withAnimation(reduceMotion ? nil : .spring(response: 0.32, dampingFraction: 0.76)) {
                        selectedKindID = nil
                    }
                }

                ForEach(kinds) { kind in
                    let isSel = selectedKindID == kind.id
                    MainKindCapsule(
                        title: kind.localizedName,
                        systemImage: fallbackSymbol(for: kind.id),
                        imageUrl: kind.imageUrl,
                        themeColor: kind.themeColor,
                        isSelected: isSel
                    ) {
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                        withAnimation(reduceMotion ? nil : .spring(response: 0.32, dampingFraction: 0.76)) {
                            selectedKindID = isSel ? nil : kind.id
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
    }

    private func fallbackSymbol(for id: Int) -> String {
        switch id {
        case 1: return "pawprint.fill"
        case 2: return "cat.fill"
        case 3: return "bird.fill"
        case 4: return "fish.fill"
        case 5: return "hare.fill"
        case 6: return "lizard.fill"
        default: return "pawprint"
        }
    }
}

private struct MainKindCapsule: View {
    let title: String
    let systemImage: String
    let imageUrl: String?
    let themeColor: Color
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 8) {
                ZStack {
                    if let urlStr = imageUrl, let url = URL(string: urlStr) {
                        AdminRemoteImage(url: url, contentMode: .fill, targetSize: CGSize(width: 44, height: 44)) {
                            ProgressView().frame(width: 24, height: 24)
                        }
                        .frame(width: 26, height: 26)
                        .clipShape(Circle())
                    } else {
                        Image(systemName: systemImage)
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(isSelected ? Color.white : themeColor)
                    }
                }
                .frame(width: 28, height: 28)
                .background(isSelected ? themeColor.opacity(0.8) : themeColor.opacity(0.15), in: Circle())

                Text(title)
                    .font(isSelected ? AdminType.captionBold : AdminType.caption)
                    .foregroundStyle(isSelected ? AdminSurface.primaryText : AdminSurface.secondaryText)
            }
            .padding(.leading, 6)
            .padding(.trailing, 14)
            .padding(.vertical, 6)
            .background(isSelected ? themeColor.opacity(0.18) : AdminSurface.backgroundSecondary, in: Capsule())
            .overlay(Capsule().stroke(isSelected ? themeColor : AdminSurface.hairline, lineWidth: isSelected ? 1.5 : 0.5))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - POS Grid Catalog Tile Pattern

struct ProformaCatalogTile: View {
    let item: ProformaCatalogItem
    let inDraft: Int
    let currency: String
    let tileHeight: CGFloat
    let onTap: () -> Void
    let onIncrement: () -> Void
    let onDecrement: () -> Void

    private var availableCount: Int {
        Int(item.availableQuantity) ?? 0
    }

    private var stockText: String {
        if availableCount <= 0 {
            return Language.get("POS_OutOfStock", alter: "نفد المخزون")
        }
        return String(
            format: Language.get("POS_RemainingStockFormat", alter: "المتبقي: %d"),
            availableCount
        )
    }

    private var stockDotColor: Color {
        if availableCount <= 0 { return .red }
        if availableCount <= 3 { return .orange }
        return Color(red: 0.1, green: 0.72, blue: 0.45)
    }

    private var stockTextColor: Color {
        if availableCount <= 0 { return .red }
        if availableCount <= 3 { return .orange }
        return AdminSurface.secondaryText
    }

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 3) {
                // Top: Image thumbnail bounded cleanly to allocated space
                GeometryReader { geo in
                    let w = max(1, geo.size.width)
                    let h = max(1, geo.size.height)

                    ZStack(alignment: .topTrailing) {
                        // Background plate
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(AdminSurface.backgroundSecondary.opacity(0.6))
                            .frame(width: w, height: h)

                        // Product image scaled to fit with aspect ratio preserved
                        if let urlStr = item.imageUrl, !urlStr.isEmpty {
                            AdminRemoteImage(
                                urlString: urlStr,
                                contentMode: .fit,
                                targetSize: UIDevice.current.userInterfaceIdiom == .pad
                                    ? CGSize(width: 180, height: 160)
                                    : CGSize(width: 140, height: 120)
                            ) {
                                Image(systemName: item.isLivePet ? "pawprint.fill" : "cube.box")
                                    .font(.system(size: 22))
                                    .foregroundColor(AdminSurface.secondaryText)
                            }
                            .padding(4)
                            .frame(width: w, height: h)
                            .clipped()
                        } else {
                            Image(systemName: item.isLivePet ? "pawprint.fill" : "cube.box")
                                .font(.system(size: 22))
                                .foregroundColor(AdminSurface.secondaryText)
                                .frame(width: w, height: h)
                        }

                        // Top-leading: unit group badge if available
                        if !item.groupName.isEmpty {
                            VStack {
                                HStack {
                                    Text(item.groupName)
                                        .font(PPBeirutiFont.bold(10, relativeTo: .caption2))
                                        .foregroundColor(.white)
                                        .padding(.horizontal, 5)
                                        .padding(.vertical, 2)
                                        .background(Color.black.opacity(0.65), in: RoundedRectangle(cornerRadius: 4, style: .continuous))
                                        .padding(4)
                                    Spacer()
                                }
                                Spacer()
                            }
                            .frame(width: w, height: h)
                        }

                        // Top-trailing: in-draft quantity badge + quick decrement button
                        if inDraft > 0 {
                            HStack(spacing: 3) {
                                Button {
                                    onDecrement()
                                } label: {
                                    Image(systemName: "minus")
                                        .font(.system(size: 8, weight: .bold))
                                        .foregroundColor(.white)
                                        .frame(width: 18, height: 18)
                                        .background(Color.black.opacity(0.65), in: Circle())
                                }
                                .buttonStyle(.plain)

                                Text("\(inDraft)")
                                    .font(AdminType.caption2Bold)
                                    .foregroundColor(.white)
                                    .frame(minWidth: 18, minHeight: 18)
                                    .background(AdminSurface.primary, in: Circle())
                            }
                            .padding(4)
                        }
                    }
                    .frame(width: w, height: h)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                // Bottom: All labels anchored to bottom
                VStack(alignment: .leading, spacing: 1.5) {
                    HStack(spacing: 2) {
                        Text(item.name)
                            .font(AdminType.caption2Bold)
                            .foregroundColor(AdminSurface.primaryText)
                            .lineLimit(1)
                            .minimumScaleFactor(0.85)

                        Spacer(minLength: 0)

                        if item.isLivePet {
                            Image(systemName: "pawprint.fill")
                                .font(.system(size: 8))
                                .foregroundColor(AdminSurface.primary)
                        }
                    }

                    HStack(spacing: 2) {
                        Text(POSReceiptFormat.currency(proformaDoublePrice(item.unitPrice), code: item.currency.isEmpty ? currency : item.currency))
                            .font(AdminType.caption2Bold)
                            .foregroundColor(AdminSurface.primary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.72)

                        Spacer(minLength: 0)
                    }

                    HStack(spacing: 3) {
                        Circle()
                            .fill(stockDotColor)
                            .frame(width: 4, height: 4)

                        Text(stockText)
                            .font(AdminType.caption2)
                            .foregroundColor(stockTextColor)
                            .lineLimit(1)
                            .minimumScaleFactor(0.72)

                        Spacer(minLength: 0)
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
                .layoutPriority(1)
            }
            .padding(6)
            .frame(height: tileHeight)
            .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(inDraft > 0 ? AdminSurface.primary.opacity(0.6) : AdminSurface.hairline, lineWidth: inDraft > 0 ? 1.5 : 0.75)
            )
            .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(ProformaTilePressStyle())
    }
}

struct ProformaTilePressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? AdminAnimation.pressScale : 1)
            .animation(AdminAnimation.fast, value: configuration.isPressed)
    }
}

// MARK: - Commercial Conversion Studio Sheet (Matching POS Refund / Cancel Pattern)

struct ProformaConversionSheet: View {
    let invoice: ProformaInvoice
    @ObservedObject var store: ProformaInvoiceStore
    let onSuccess: (POSCompletedReceipt) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var paymentMethod = "cash"
    @State private var cashReceived = ""
    @State private var isConverting = false

    private var invoiceTotalDecimal: Decimal {
        ProformaDecimal.minor(invoice.totals.totalMinor)
    }

    private var cashReceivedDecimal: Decimal? {
        ProformaDecimal.parse(cashReceived, scale: 2)
    }

    private var changeDueDecimal: Decimal {
        guard let received = cashReceivedDecimal, received >= invoiceTotalDecimal else { return 0 }
        return received - invoiceTotalDecimal
    }

    private var isValidCash: Bool {
        guard paymentMethod == "cash" else { return true }
        guard let received = cashReceivedDecimal else { return false }
        return received >= invoiceTotalDecimal && received <= Decimal(string: "999999999.99")!
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Document Header
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(invoice.displayNumber)
                                .font(PPBeirutiFont.bold(20, relativeTo: .title3))
                                .environment(\.layoutDirection, .leftToRight)
                            Text(invoice.customer?.name.isEmpty == false ? invoice.customer!.name : Language.get("Proforma_NoCustomer", alter: "لم يُحدّد العميل"))
                                .font(PPBeirutiFont.regular(15, relativeTo: .subheadline))
                                .foregroundStyle(AdminSurface.secondaryText)
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 2) {
                            Text(Language.get("Proforma_Total", alter: "الإجمالي"))
                                .font(PPBeirutiFont.bold(13, relativeTo: .caption))
                                .foregroundStyle(AdminSurface.secondaryText)
                            POSJournalAmount(value: Double(invoice.totals.totalMinor) / 100.0, currency: invoice.currency, amountFont: AdminType.title)
                                .foregroundStyle(AdminSurface.emerald)
                        }
                    }
                    .padding(16)
                    .background(AdminSurface.backgroundSecondary, in: RoundedRectangle(cornerRadius: 16, style: .continuous))

                    Text(Language.get("Proforma_ConvertWarning", alter: "أكّد البيع بعد استلام الدفع فقط. يخصم التحويل المخزون المتاح ويُنشئ البيع الفعلي."))
                        .font(PPBeirutiFont.regular(13.5, relativeTo: .footnote))
                        .foregroundStyle(AdminSurface.secondaryText)

                    // Payment Method
                    VStack(alignment: .leading, spacing: 8) {
                        Text(Language.get("Proforma_Payment", alter: "طريقة الدفع"))
                            .font(PPBeirutiFont.bold(16, relativeTo: .headline))
                            .foregroundStyle(AdminSurface.primaryText)

                        HStack(spacing: 12) {
                            PaymentMethodCard(
                                title: Language.get("Proforma_Cash", alter: "نقدي"),
                                systemImage: "banknote.fill",
                                isSelected: paymentMethod == "cash"
                            ) {
                                paymentMethod = "cash"
                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            }

                            PaymentMethodCard(
                                title: Language.get("Proforma_Card", alter: "بطاقة بنكية"),
                                systemImage: "creditcard.fill",
                                isSelected: paymentMethod == "card"
                            ) {
                                paymentMethod = "card"
                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            }
                        }
                    }

                    // Cash Handling
                    if paymentMethod == "cash" {
                        VStack(alignment: .leading, spacing: 14) {
                            VStack(alignment: .leading, spacing: 6) {
                                Text(Language.get("Proforma_CashReceived", alter: "المبلغ المستلم نقداً"))
                                    .font(PPBeirutiFont.bold(15, relativeTo: .subheadline))
                                    .foregroundStyle(AdminSurface.primaryText)
                                TextField(Language.get("Proforma_CashReceived", alter: "المبلغ"), text: $cashReceived)
                                    .keyboardType(.decimalPad)
                                    .font(AdminType.title3)
                                    .environment(\.layoutDirection, .leftToRight)
                                    .padding(.horizontal, 14)
                                    .frame(height: 50)
                                    .background(AdminSurface.backgroundSecondary, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                            }

                            VStack(alignment: .leading, spacing: 6) {
                                Text(Language.get("POS_QuickAdd", alter: "إضافة سريعة"))
                                    .font(PPBeirutiFont.medium(12, relativeTo: .caption))
                                    .foregroundStyle(AdminSurface.secondaryText)

                                HStack(spacing: 8) {
                                    QuickTenderButton(title: Language.get("Proforma_QuickTenderExact", alter: "المبلغ المطلوب تماماً")) {
                                        cashReceived = ProformaDecimal.string(invoiceTotalDecimal)
                                    }
                                    QuickTenderButton(title: Language.get("Proforma_QuickTenderPlus10", alter: "+10")) {
                                        let base = cashReceivedDecimal ?? invoiceTotalDecimal
                                        cashReceived = ProformaDecimal.string(base + 10)
                                    }
                                    QuickTenderButton(title: Language.get("Proforma_QuickTenderPlus50", alter: "+50")) {
                                        let base = cashReceivedDecimal ?? invoiceTotalDecimal
                                        cashReceived = ProformaDecimal.string(base + 50)
                                    }
                                    QuickTenderButton(title: Language.get("Proforma_QuickTenderPlus100", alter: "+100")) {
                                        let base = cashReceivedDecimal ?? invoiceTotalDecimal
                                        cashReceived = ProformaDecimal.string(base + 100)
                                    }
                                }
                            }

                            if changeDueDecimal >= 0 {
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(Language.get("POS_ChangeDue", alter: "المتبقي للعميل"))
                                            .font(PPBeirutiFont.medium(14, relativeTo: .subheadline))
                                            .foregroundStyle(AdminSurface.secondaryText)
                                        POSJournalAmount(value: NSDecimalNumber(decimal: changeDueDecimal).doubleValue, currency: invoice.currency, amountFont: AdminType.title2)
                                            .foregroundStyle(AdminSurface.emerald)
                                    }
                                    Spacer()
                                    Image(systemName: "checkmark.circle.fill")
                                        .font(.system(size: 28))
                                        .foregroundStyle(AdminSurface.emerald)
                                }
                                .padding(14)
                                .background(AdminSurface.emerald.opacity(0.1), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                            }
                        }
                    }

                    if isConverting || store.isMutating {
                        HStack(spacing: 12) {
                            ProgressView().tint(AdminSurface.primary)
                            Text(Language.get("Proforma_Converting", alter: "جارٍ إنشاء البيع الفعلي…"))
                                .font(AdminType.body)
                                .foregroundStyle(AdminSurface.secondaryText)
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                    }

                    if let err = store.error {
                        ProformaErrorBanner(
                            message: err,
                            canRetry: store.canRetryMutation,
                            isConflict: false,
                            onRetry: { Task { await executeConversion() } },
                            onReload: {}
                        )
                    }

                    Button {
                        promptConversionConfirmation()
                    } label: {
                        Label(Language.get("Proforma_ConfirmSale", alter: "تأكيد البيع الفعلي"), systemImage: "checkmark.seal.fill")
                            .font(PPBeirutiFont.bold(16, relativeTo: .headline))
                            .frame(maxWidth: .infinity, minHeight: 52)
                            .foregroundStyle(Color.white)
                            .background(
                                isValidCash && !store.isLocked ? AdminSurface.emerald : AdminSurface.secondaryText,
                                in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                            )
                    }
                    .buttonStyle(.plain)
                    .disabled(store.isLocked || !isValidCash || invoice.status != .issued || isConverting)
                    .padding(.top, 10)
                }
                .padding(24)
            }
            .navigationTitle(Language.get("Proforma_Convert", alter: "تحويل إلى بيع"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text(Language.get("Proforma_Convert", alter: "تحويل إلى بيع"))
                        .font(PPBeirutiFont.bold(18, relativeTo: .headline))
                        .foregroundStyle(AdminSurface.primaryText)
                }
                ToolbarItem(placement: .cancellationAction) {
                    AdminSquircleCloseButton { dismiss() }
                        .disabled(isConverting || store.isLocked)
                }
            }
            .onAppear {
                cashReceived = ProformaDecimal.string(invoiceTotalDecimal)
            }
        }
    }

    private func promptConversionConfirmation() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        let title = Language.get("Proforma_ConfirmSale", alter: "تأكيد البيع الفعلي")
        let message = Language.get("Proforma_ConvertWarning_Extended", alter: "أكّد البيع بعد استلام الدفع فقط. يخصم التحويل المخزون المتاح ويُنشئ البيع الفعلي وسجلاته المحاسبية مرة واحدة.")
        PPAlertHelper.showConfirmation(
            in: nil,
            title: title,
            subtitle: message,
            confirmButton: Language.get("Proforma_ConfirmSale", alter: "تأكيد البيع الفعلي"),
            cancelButton: Language.get("Cancel", alter: "إلغاء"),
            icon: UIImage(systemName: "checkmark.seal.fill"),
            confirmBlock: { _, didConfirm in
                guard didConfirm else { return }
                Task { @MainActor in
                    await self.executeConversion()
                }
            },
            cancelBlock: nil
        )
    }

    private func executeConversion() async {
        isConverting = true
        defer { isConverting = false }
        UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
        await store.perform("convert", paymentMethod: paymentMethod, cashReceived: cashReceived)

        if let convertedID = store.selected?.convertedTransactionId ?? store.invoices.first(where: { $0.id == invoice.id })?.convertedTransactionId {
            PPPOSService.shared().fetchPOSReceipt(forTransactionID: convertedID) { receipt, error in
                Task { @MainActor in
                    if let receipt {
                        dismiss()
                        onSuccess(POSCompletedReceipt(receipt: receipt))
                    }
                }
            }
        } else if let err = store.error {
            await PPAlertHelper.showError(in: nil, title: Language.get("Error", alter: "خطأ"), subtitle: err)
        }
    }
}

private struct PaymentMethodCard: View {
    let title: String
    let systemImage: String
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 8) {
                Image(systemName: systemImage)
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(isSelected ? Color.white : AdminSurface.primary)
                Text(title)
                    .font(PPBeirutiFont.bold(15, relativeTo: .subheadline))
                    .foregroundStyle(isSelected ? Color.white : AdminSurface.primaryText)
            }
            .frame(maxWidth: .infinity, minHeight: 74)
            .background(
                isSelected ? AdminSurface.primary : AdminSurface.backgroundSecondary,
                in: RoundedRectangle(cornerRadius: 14, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(isSelected ? AdminSurface.primary : AdminSurface.hairline, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

private struct QuickTenderButton: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            action()
        }) {
            Text(title)
                .font(PPBeirutiFont.bold(13, relativeTo: .caption))
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(AdminSurface.backgroundSecondary, in: Capsule())
                .overlay(Capsule().stroke(AdminSurface.hairline, lineWidth: 0.5))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Proforma Cancel Confirmation Sheet

struct ProformaCancelConfirmationSheet: View {
    let invoice: ProformaInvoice
    @ObservedObject var store: ProformaInvoiceStore
    let onSuccess: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var isCancelling = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Image(systemName: "xmark.octagon.fill")
                    .font(.system(size: 52))
                    .foregroundColor(AdminSurface.danger)
                    .padding(.top, 24)

                VStack(spacing: 8) {
                    Text(Language.get("Proforma_CancelInvoice_Title", alter: "إلغاء الفاتورة المبدئية؟"))
                        .font(PPBeirutiFont.bold(20, relativeTo: .title3))
                        .foregroundColor(AdminSurface.primaryText)

                    Text(Language.get("Proforma_CancelInvoice_Message", alter: "يبقى المستند المحفوظ في القائمة بحالة ملغاة. لا يُنشأ بيع ولا حركة مخزون."))
                        .font(AdminType.body)
                        .foregroundColor(AdminSurface.secondaryText)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                }

                HStack {
                    Text(invoice.displayNumber)
                        .font(PPBeirutiFont.bold(17, relativeTo: .headline))
                        .environment(\.layoutDirection, .leftToRight)
                    Spacer()
                    POSJournalAmount(value: Double(invoice.totals.totalMinor) / 100.0, currency: invoice.currency)
                }
                .padding(16)
                .background(AdminSurface.backgroundSecondary, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .padding(.horizontal, 20)

                Spacer()

                VStack(spacing: 12) {
                    if let error = store.error {
                        HStack(spacing: 8) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(AdminSurface.danger)
                            Text(error)
                                .font(PPBeirutiFont.regular(13, relativeTo: .caption))
                                .foregroundColor(AdminSurface.danger)
                        }
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(AdminSurface.danger.opacity(0.1), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }

                    Button {
                        promptDestructiveCancel()
                    } label: {
                        HStack(spacing: 8) {
                            if isCancelling {
                                ProgressView().tint(.white)
                            } else {
                                Image(systemName: "xmark.circle.fill")
                            }
                            Text(Language.get("Proforma_CancelInvoice", alter: "تأكيد إلغاء الفاتورة"))
                                .font(PPBeirutiFont.bold(16, relativeTo: .headline))
                        }
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                        .background(isCancelling ? AdminSurface.secondaryText : AdminSurface.danger, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .disabled(isCancelling)

                    Button {
                        dismiss()
                    } label: {
                        Text(Language.get("Cancel", alter: "تراجع"))
                            .font(PPBeirutiFont.bold(16, relativeTo: .headline))
                            .foregroundColor(AdminSurface.primaryText)
                            .frame(maxWidth: .infinity)
                            .frame(height: 48)
                    }
                    .buttonStyle(.plain)
                    .disabled(isCancelling)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 16)
            }
            .navigationTitle(Language.get("Proforma_CancelInvoice", alter: "إلغاء الفاتورة"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text(Language.get("Proforma_CancelInvoice", alter: "إلغاء الفاتورة"))
                        .font(PPBeirutiFont.bold(18, relativeTo: .headline))
                        .foregroundStyle(AdminSurface.primaryText)
                }
                ToolbarItem(placement: .cancellationAction) {
                    AdminSquircleCloseButton { dismiss() }
                }
            }
        }
    }

    private func promptDestructiveCancel() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        let title = Language.get("Proforma_CancelInvoice_Title", alter: "إلغاء الفاتورة المبدئية؟")
        let message = "\(invoice.displayNumber)\n" + Language.get("Proforma_CancelInvoice_Message", alter: "يبقى المستند المحفوظ في القائمة بحالة ملغاة. لا يُنشأ بيع ولا حركة مخزون.")
        PPAlertHelper.showDestructiveConfirmation(
            in: nil,
            title: title,
            subtitle: message,
            confirmButton: Language.get("Proforma_CancelInvoice", alter: "تأكيد إلغاء الفاتورة"),
            cancelButton: Language.get("Cancel", alter: "تراجع"),
            icon: UIImage(systemName: "xmark.octagon.fill"),
            confirmBlock: { _, didConfirm in
                guard didConfirm else { return }
                Task { @MainActor in
                    isCancelling = true
                    let success = await store.cancelInvoice(invoice)
                    isCancelling = false
                    if success {
                        dismiss()
                        onSuccess()
                    } else if let error = store.error {
                        await PPAlertHelper.showError(in: nil, title: Language.get("Error", alter: "خطأ"), subtitle: error)
                    }
                }
            },
            cancelBlock: nil
        )
    }
}

// MARK: - Reusable Document Components (Customer, Terms, Line Items, Summary, Command Dock)

struct ProformaCustomerStudioCard: View {
    let customer: ProformaCustomer?
    let editable: Bool
    let onSelect: () -> Void
    let onRemove: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(Language.get("Proforma_Customer", alter: "بيانات العميل")).font(AdminType.headline)
                Spacer()
                if customer != nil && editable {
                    Button(Language.get("Proforma_RemoveCustomer", alter: "إزالة"), action: onRemove)
                        .font(AdminType.footnoteBold)
                        .foregroundStyle(AdminSurface.danger)
                }
            }

            Button(action: {
                if editable {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    onSelect()
                }
            }) {
                HStack(spacing: 12) {
                    Circle()
                        .fill(AdminSurface.primary.opacity(0.15))
                        .frame(width: 44, height: 44)
                        .overlay(
                            Image(systemName: "person.fill")
                                .font(.system(size: 18))
                                .foregroundStyle(AdminSurface.primary)
                        )

                    VStack(alignment: .leading, spacing: 2) {
                        Text(customer?.name ?? Language.get("Proforma_SelectCustomer", alter: "اختر عميلاً"))
                            .font(AdminType.headline)
                            .foregroundStyle(AdminSurface.primaryText)
                        if let cust = customer, !cust.phone.isEmpty {
                            Text(cust.phone)
                                .font(AdminType.subheadline)
                                .foregroundStyle(AdminSurface.secondaryText)
                                .environment(\.layoutDirection, .leftToRight)
                        }
                    }

                    Spacer()

                    if editable {
                        Image(systemName: "chevron.forward")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(AdminSurface.secondaryText)
                    }
                }
                .padding(14)
                .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(AdminSurface.hairline, lineWidth: 1))
            }
            .buttonStyle(.plain)
            .disabled(!editable)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct ProformaTermsStudioCard: View {
    @Binding var draft: ProformaDraft
    let editable: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(Language.get("Proforma_Terms", alter: "شروط العرض")).font(AdminType.headline)

            VStack(alignment: .leading, spacing: 6) {
                Toggle(Language.get("Proforma_Validity", alter: "تحديد تاريخ الصلاحية"), isOn: Binding(
                    get: { draft.validUntil != nil },
                    set: { enabled in
                        draft.validUntil = enabled ? ProformaWire.validityString(Date()) : nil
                    }
                ))
                .font(AdminType.subheadlineBold)
                .disabled(!editable)

                if draft.validUntil != nil {
                    HStack(spacing: 8) {
                        PresetValidityButton(title: "7 أيام") { setDays(7) }
                        PresetValidityButton(title: "14 يوماً") { setDays(14) }
                        PresetValidityButton(title: "30 يوماً") { setDays(30) }
                    }
                    .padding(.top, 2)

                    DatePicker(
                        Language.get("Proforma_ValidUntil", alter: "صالحة حتى"),
                        selection: Binding(
                            get: { ProformaWire.validityDate(draft.validUntil) ?? Date() },
                            set: { draft.validUntil = ProformaWire.validityString($0) }
                        ),
                        displayedComponents: .date
                    )
                    .datePickerStyle(.compact)
                    .font(AdminType.body)
                    .disabled(!editable)
                    .environment(\.timeZone, TimeZone(secondsFromGMT: 0)!)
                }
            }

            ProformaDiscountEditor(
                title: "Proforma_InvoiceDiscount",
                discount: $draft.discount,
                editable: editable
            )

            VStack(alignment: .leading, spacing: 4) {
                Text(Language.get("Proforma_Notes", alter: "ملاحظات")).font(AdminType.subheadlineBold)
                TextField(Language.get("Proforma_NotesPlaceholder", alter: "شروط أو رسالة للعميل"), text: Binding(
                    get: { draft.notes },
                    set: { draft.notes = String($0.prefix(2000)) }
                ), axis: .vertical)
                .font(AdminType.body)
                .lineLimit(2...5)
                .padding(10)
                .background(AdminSurface.backgroundSecondary, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .disabled(!editable)
            }
        }
        .padding(14)
        .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(AdminSurface.hairline, lineWidth: 1))
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func setDays(_ count: Int) {
        guard editable else { return }
        let target = Calendar.current.date(byAdding: .day, value: count, to: Date()) ?? Date()
        draft.validUntil = ProformaWire.validityString(target)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }
}

private struct PresetValidityButton: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(AdminType.captionBold)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(AdminSurface.backgroundSecondary, in: Capsule())
                .overlay(Capsule().stroke(AdminSurface.hairline, lineWidth: 0.5))
        }
        .buttonStyle(.plain)
    }
}

struct ProformaLineItemsStudio: View {
    @Binding var items: [ProformaLine]
    let currency: String
    let editable: Bool
    let onAddItem: () -> Void
    let onRemoveItem: (ProformaLine) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(Language.get("Proforma_Items", alter: "المنتجات")).font(AdminType.headline)
                    Text(String(format: Language.get("POS_Dossier_ItemsCount", alter: "%d عنصر"), items.count))
                        .font(AdminType.caption)
                        .foregroundStyle(AdminSurface.secondaryText)
                }
                Spacer()
                if editable {
                    Button(action: onAddItem) {
                        Label(Language.get("Proforma_AddItem", alter: "إضافة منتج"), systemImage: "plus.circle.fill")
                            .font(AdminType.subheadlineBold)
                            .foregroundStyle(Color.white)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(AdminSurface.primary, in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }

            if items.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "cart.badge.plus")
                        .font(.system(size: 32))
                        .foregroundStyle(AdminSurface.secondaryText)
                    Text(Language.get("Proforma_ItemsEmpty", alter: "اختر المنتجات من قائمة هذا الفرع."))
                        .font(AdminType.body)
                        .foregroundStyle(AdminSurface.secondaryText)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 28)
                .background(AdminSurface.backgroundSecondary.opacity(0.5), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            } else {
                VStack(spacing: 12) {
                    ForEach(items) { line in
                        ProformaLineEditor(
                            line: bindingForLine(line),
                            currency: currency,
                            editable: editable,
                            onRemove: { onRemoveItem(line) }
                        )
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func bindingForLine(_ item: ProformaLine) -> Binding<ProformaLine> {
        Binding(
            get: { items.first(where: { $0.id == item.id }) ?? item },
            set: { updated in
                if let idx = items.firstIndex(where: { $0.id == item.id }) {
                    items[idx] = updated
                }
            }
        )
    }
}

struct ProformaLineEditor: View {
    @Binding var line: ProformaLine
    let currency: String
    let editable: Bool
    let onRemove: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                if let urlStr = line.imageUrl, !urlStr.isEmpty {
                    AdminRemoteImage(urlString: urlStr, contentMode: .fill, targetSize: CGSize(width: 80, height: 80)) {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(AdminSurface.backgroundSecondary)
                            .overlay(Image(systemName: "cube.box").font(.system(size: 16)).foregroundStyle(AdminSurface.secondaryText))
                    }
                    .frame(width: 48, height: 48)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(line.name)
                        .font(AdminType.headline)
                        .foregroundStyle(AdminSurface.primaryText)
                    if !line.groupName.isEmpty {
                        Text(line.groupName)
                            .font(AdminType.captionBold)
                            .foregroundStyle(AdminSurface.primary)
                    }
                    if !line.sku.isEmpty {
                        Text(line.sku)
                            .font(AdminType.caption)
                            .foregroundStyle(AdminSurface.secondaryText)
                            .environment(\.layoutDirection, .leftToRight)
                    }
                }

                Spacer()

                if editable {
                    Button(action: onRemove) {
                        Image(systemName: "trash")
                            .font(.system(size: 14))
                            .foregroundStyle(AdminSurface.danger)
                            .frame(width: 36, height: 36)
                            .background(AdminSurface.danger.opacity(0.1), in: Circle())
                    }
                }
            }

            Divider().background(AdminSurface.hairline)

            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(Language.get("Proforma_Quantity", alter: "الكمية")).font(AdminType.captionBold).foregroundStyle(AdminSurface.secondaryText)
                    if line.unitIds.isEmpty {
                        HStack(spacing: 6) {
                            Button {
                                let cur = ProformaDecimal.parse(line.quantity, scale: 3) ?? 1
                                if cur > 1 {
                                    line.quantity = ProformaDecimal.string(cur - 1)
                                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                }
                            } label: {
                                Image(systemName: "minus")
                                    .font(.system(size: 12, weight: .bold))
                                    .frame(width: 28, height: 28)
                                    .background(AdminSurface.backgroundSecondary, in: Circle())
                            }
                            .disabled(!editable)

                            TextField("1", text: $line.quantity)
                                .keyboardType(.decimalPad)
                                .font(AdminType.headline)
                                .multilineTextAlignment(.center)
                                .frame(width: 50, height: 34)
                                .background(AdminSurface.backgroundSecondary, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                                .disabled(!editable)

                            Button {
                                let cur = ProformaDecimal.parse(line.quantity, scale: 3) ?? 1
                                line.quantity = ProformaDecimal.string(cur + 1)
                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            } label: {
                                Image(systemName: "plus")
                                    .font(.system(size: 12, weight: .bold))
                                    .frame(width: 28, height: 28)
                                    .background(AdminSurface.backgroundSecondary, in: Circle())
                            }
                            .disabled(!editable)
                        }
                    } else {
                        Text(String(format: pf("Proforma_ExactUnits"), line.unitIds.count))
                            .font(AdminType.captionBold)
                            .foregroundStyle(AdminSurface.primary)
                    }
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(Language.get("Proforma_UnitPrice", alter: "سعر الوحدة")).font(AdminType.captionBold).foregroundStyle(AdminSurface.secondaryText)
                    TextField("0.00", text: $line.unitPrice)
                        .keyboardType(.decimalPad)
                        .font(AdminType.headline)
                        .environment(\.layoutDirection, .leftToRight)
                        .padding(.horizontal, 8)
                        .frame(height: 34)
                        .background(AdminSurface.backgroundSecondary, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                        .disabled(!editable || !line.unitIds.isEmpty)
                }

                ProformaDiscountEditor(
                    title: "Proforma_LineDiscount",
                    discount: $line.discount,
                    editable: editable
                )
            }
        }
        .padding(14)
        .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(AdminSurface.hairline, lineWidth: 1))
    }
}

struct ProformaDiscountEditor: View {
    let title: String
    @Binding var discount: ProformaDiscount
    let editable: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(Language.get(title, alter: "الخصم")).font(AdminType.captionBold).foregroundStyle(AdminSurface.secondaryText)
                Spacer()
                Menu {
                    Button(Language.get("Proforma_Discount_none", alter: "دون خصم")) { discount.type = "none"; discount.value = "0" }
                    Button(Language.get("Proforma_Discount_percent", alter: "نسبة مئوية")) { discount.type = "percent"; discount.value = "0" }
                    Button(Language.get("Proforma_Discount_amount", alter: "مبلغ ثابت")) { discount.type = "amount"; discount.value = "0" }
                } label: {
                    HStack(spacing: 4) {
                        Text(discount.type == "none" ? Language.get("Proforma_Discount_none", alter: "دون") : (discount.type == "percent" ? "%" : Language.get("QAR", alter: "ر.ق")))
                            .font(AdminType.captionBold)
                        Image(systemName: "chevron.down").font(.system(size: 10))
                    }
                    .foregroundStyle(AdminSurface.primary)
                }
                .disabled(!editable)
            }

            if discount.type != "none" {
                TextField("0", text: $discount.value)
                    .keyboardType(.decimalPad)
                    .font(AdminType.headline)
                    .environment(\.layoutDirection, .leftToRight)
                    .padding(.horizontal, 8)
                    .frame(height: 34)
                    .background(AdminSurface.backgroundSecondary, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .disabled(!editable)
            }
        }
    }
}

struct ProformaFinancialSummaryCard: View {
    let draft: ProformaDraft
    let selected: ProformaInvoice?
    let hasUnsaved: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(hasUnsaved ? Language.get("Proforma_Estimate", alter: "الإجماليات التقديرية") : Language.get("Proforma_Totals", alter: "الإجماليات المؤكدة"))
                .font(AdminType.headline)

            if hasUnsaved {
                if let totals = try? draft.estimatedTotals() {
                    totalsRows(totals: totals, currency: draft.currency)
                } else {
                    Text(Language.get("Proforma_Error_InvalidInput", alter: "بيانات غير مكتملة"))
                        .font(AdminType.footnote)
                        .foregroundStyle(AdminSurface.danger)
                }
                Text(Language.get("Proforma_EstimateHint", alter: "احفظ لتأكيد الأسعار والخصومات."))
                    .font(AdminType.caption)
                    .foregroundStyle(AdminSurface.secondaryText)
            } else if let inv = selected {
                totalsRows(totals: inv.totals, currency: inv.currency)
            }
        }
        .padding(16)
        .background(AdminSurface.backgroundSecondary, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func totalsRows(totals: ProformaTotals, currency: String) -> some View {
        VStack(spacing: 8) {
            row(Language.get("Proforma_Subtotal", alter: "المجموع الفرعي"), value: totals.subtotalMinor, currency: currency)
            row(Language.get("Proforma_Discount", alter: "الخصومات"), value: -(totals.lineDiscountMinor + totals.discountMinor), currency: currency, color: Color(uiColor: .systemGreen))
            row(Language.get("Proforma_Tax", alter: "الضريبة"), value: totals.taxMinor, currency: currency)
            Divider().background(AdminSurface.hairline)
            HStack {
                Text(Language.get("Proforma_Total", alter: "الإجمالي")).font(AdminType.title3)
                Spacer()
                POSJournalAmount(value: Double(totals.totalMinor) / 100.0, currency: currency, amountFont: AdminType.title2)
                    .foregroundStyle(AdminSurface.emerald)
            }
        }
    }

    private func row(_ title: String, value: Int, currency: String, color: Color = AdminSurface.primaryText) -> some View {
        HStack {
            Text(title).font(AdminType.body)
            Spacer()
            POSJournalAmount(value: Double(value) / 100.0, currency: currency, amountFont: AdminType.bodyBold)
                .foregroundStyle(color)
        }
    }
}

struct ProformaCommandDock: View {
    @ObservedObject var store: ProformaInvoiceStore
    let editable: Bool
    let canWrite: Bool

    let onSave: () -> Void
    let onIssue: () -> Void
    let onConvert: () -> Void
    let onPreview: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: 8) {
            if store.isMutating {
                ProgressView(Language.get("Proforma_Saving", alter: "جارٍ حفظ التغييرات…"))
            }

            HStack(spacing: 12) {
                if editable && (store.hasUnsavedChanges || store.selected == nil) {
                    Button(action: onSave) {
                        Label(Language.get("Proforma_SaveDraft", alter: "حفظ المسودة"), systemImage: "checkmark")
                            .font(AdminType.headline)
                            .frame(maxWidth: .infinity, minHeight: 48)
                            .foregroundStyle(Color.white)
                            .background(AdminSurface.primary, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    .buttonStyle(.plain)
                } else if let sel = store.selected {
                    Button(action: onPreview) {
                        Label(Language.get("Proforma_Preview", alter: "معاينة PDF"), systemImage: "doc.text.magnifyingglass")
                            .font(AdminType.headline)
                            .frame(maxWidth: .infinity, minHeight: 48)
                            .foregroundStyle(AdminSurface.primaryText)
                            .background(AdminSurface.backgroundSecondary, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .disabled(store.isLocked)

                    if canWrite && sel.status == .draft {
                        Button(action: onIssue) {
                            Label(Language.get("Proforma_Issue", alter: "إصدار الفاتورة المبدئية"), systemImage: "checkmark.seal.fill")
                                .font(AdminType.headline)
                                .frame(maxWidth: .infinity, minHeight: 48)
                                .foregroundStyle(Color.white)
                                .background(AdminSurface.primary, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .disabled(store.isLocked || sel.isExpired)
                    } else if canWrite && sel.status == .issued {
                        Button(action: onConvert) {
                            Label(Language.get("Proforma_Convert", alter: "تحويل إلى بيع"), systemImage: "arrow.right.doc.on.clipboard")
                                .font(AdminType.headline)
                                .frame(maxWidth: .infinity, minHeight: 48)
                                .foregroundStyle(Color.white)
                                .background(AdminSurface.emerald, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .disabled(store.isLocked || sel.isExpired)
                    }

                    if canWrite && sel.status.isEditable && !store.hasUnsavedChanges {
                        Menu {
                            Button(Language.get("Proforma_CancelInvoice", alter: "إلغاء الفاتورة"), role: .destructive, action: onCancel)
                        } label: {
                            Image(systemName: "ellipsis")
                                .font(.system(size: 18, weight: .bold))
                                .frame(width: 48, height: 48)
                                .background(AdminSurface.backgroundSecondary, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        }
                    }
                }
            }
        }
        .padding(14)
        .background(AdminSurface.surface)
        .overlay(alignment: .top) { Divider().background(AdminSurface.hairline) }
    }
}

// MARK: - Shimmer Skeleton & Feedback States

struct ProformaCatalogGridShimmer: View {
    let columns: [GridItem]
    let tileHeight: CGFloat
    @State private var opacity: Double = 0.45

    var body: some View {
        LazyVGrid(columns: columns, spacing: 8) {
            ForEach(0..<12, id: \.self) { _ in
                VStack(alignment: .leading, spacing: 4) {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(AdminSurface.backgroundSecondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)

                    VStack(alignment: .leading, spacing: 3) {
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(AdminSurface.backgroundSecondary)
                            .frame(maxWidth: .infinity)
                            .frame(height: 10)

                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(AdminSurface.backgroundSecondary)
                            .frame(width: 50, height: 10)

                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(AdminSurface.backgroundSecondary)
                            .frame(width: 35, height: 8)
                    }
                    .padding(.top, 2)
                }
                .padding(6)
                .frame(height: tileHeight)
                .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(AdminSurface.hairline, lineWidth: 0.75)
                )
                .opacity(opacity)
            }
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {
                opacity = 0.95
            }
        }
    }
}

struct ProformaCatalogShimmer: View {
    var body: some View {
        ProformaCatalogGridShimmer(
            columns: UIDevice.current.userInterfaceIdiom == .pad ? Array(repeating: GridItem(.flexible(), spacing: 8), count: 5) : [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)],
            tileHeight: UIDevice.current.userInterfaceIdiom == .pad ? 160 : 134
        )
    }
}

struct ProformaEmptyStateView: View {
    let title: String
    let detail: String
    let systemImage: String

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 40, weight: .light))
                .foregroundStyle(AdminSurface.primary)
            Text(Language.get(title, alter: nil))
                .font(AdminType.title3)
                .foregroundStyle(AdminSurface.primaryText)
            Text(Language.get(detail, alter: nil))
                .font(AdminType.body)
                .foregroundStyle(AdminSurface.secondaryText)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 28)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
    }
}

struct ProformaErrorBanner: View {
    let message: String
    let canRetry: Bool
    let isConflict: Bool
    let onRetry: () -> Void
    let onReload: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(AdminSurface.danger)
                Text(message)
                    .font(AdminType.footnoteBold)
                    .foregroundStyle(AdminSurface.danger)
            }

            if canRetry {
                Button(Language.get("Proforma_Retry", alter: "إعادة المحاولة"), action: onRetry)
                    .font(AdminType.subheadlineBold)
                    .foregroundStyle(AdminSurface.danger)
            } else if isConflict {
                Button(Language.get("Proforma_ReloadInvoice", alter: "إعادة التحميل"), action: onReload)
                    .font(AdminType.subheadlineBold)
                    .foregroundStyle(AdminSurface.danger)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AdminSurface.danger.opacity(0.08), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

struct ProformaConfirmationPendingBanner: View {
    let onRetry: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .foregroundStyle(AdminSurface.primary)
                Text(Language.get("Proforma_Confirming", alter: "جارٍ تأكيد المستند المحفوظ…"))
                    .font(AdminType.headline)
            }
            Text(Language.get("Proforma_ConfirmingHint", alter: "قُبل الأمر. حدّث لتأكيد النسخة المحفوظة."))
                .font(AdminType.footnote)
                .foregroundStyle(AdminSurface.secondaryText)
            Button(Language.get("Proforma_Refresh", alter: "تحديث"), action: onRetry)
                .font(AdminType.subheadlineBold)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AdminSurface.backgroundSecondary, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

// MARK: - Reusable PDF Preview & Print Presenter

struct ProformaPreviewDocument: Identifiable {
    let id = UUID()
    let data: Data
    let number: String
}

struct ProformaPDFViewerSheet: View {
    let document: ProformaPreviewDocument
    let onClose: () -> Void
    let onShare: (ProformaPreviewDocument) -> Void

    var body: some View {
        NavigationStack {
            PPProformaPDFPreview(data: document.data)
                .navigationTitle(document.number)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .principal) {
                        Text(document.number)
                            .font(PPBeirutiFont.bold(17, relativeTo: .headline))
                            .foregroundStyle(AdminSurface.primaryText)
                    }
                    ToolbarItem(placement: .cancellationAction) {
                        Button(pf("Proforma_Close"), action: onClose)
                            .font(PPBeirutiFont.bold(15, relativeTo: .headline))
                    }
                    ToolbarItemGroup(placement: .primaryAction) {
                        Button {
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            PPProformaPDFPrinter.print(data: document.data, jobName: document.number)
                        } label: {
                            Label(Language.get("Proforma_Print", alter: "طباعة"), systemImage: "printer")
                                .font(PPBeirutiFont.bold(15, relativeTo: .headline))
                        }

                        Button {
                            onShare(document)
                        } label: {
                            Label(pf("Proforma_Share"), systemImage: "square.and.arrow.up")
                                .font(PPBeirutiFont.bold(15, relativeTo: .headline))
                        }
                    }
                }
        }
        .environment(\.layoutDirection, Language.isRTL() ? .rightToLeft : .leftToRight)
    }
}

struct ProformaPDFPresenterModifier: ViewModifier {
    @Binding var previewDocument: ProformaPreviewDocument?
    @Binding var shareDocument: PPProformaPDFDocument?
    @State private var pendingShare: ProformaPreviewDocument? = nil

    func body(content: Content) -> some View {
        content
            .sheet(item: $previewDocument, onDismiss: {
                if let pending = pendingShare {
                    pendingShare = nil
                    do {
                        shareDocument = try PPProformaPDFDocument(data: pending.data, number: pending.number)
                    } catch {
                        // Handled
                    }
                }
            }) { doc in
                ProformaPDFViewerSheet(
                    document: doc,
                    onClose: { previewDocument = nil },
                    onShare: { target in
                        pendingShare = target
                        previewDocument = nil
                    }
                )
            }
            .sheet(item: $shareDocument) { doc in
                PPProformaPDFShareSheet(document: doc)
            }
    }
}

extension View {
    func proformaPDFPresenter(
        previewDocument: Binding<ProformaPreviewDocument?>,
        shareDocument: Binding<PPProformaPDFDocument?>
    ) -> some View {
        modifier(ProformaPDFPresenterModifier(previewDocument: previewDocument, shareDocument: shareDocument))
    }
}

private func pf(_ key: String) -> String {
    Language.get(key, alter: nil)
}

private extension Color {
    init?(hex: String) {
        var clean = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if clean.hasPrefix("#") { clean.removeFirst() }
        guard clean.count == 6, let rgb = UInt64(clean, radix: 16) else { return nil }
        self.init(
            red: Double((rgb >> 16) & 0xFF) / 255.0,
            green: Double((rgb >> 8) & 0xFF) / 255.0,
            blue: Double(rgb & 0xFF) / 255.0
        )
    }
}
