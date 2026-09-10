//
//  POSHistoryView.swift
//  PurePetsAdmin
//
//  Sovereign POS Financial Command Ledger & Thermal Vault.
//  Reinvented from absolute first principles:
//  - Sovereign Financial Pulse Instrument with live liquidity figure
//  - Interactive Cash vs Card proportional spectrum bar
//  - Horizon Time Capsule Ribbon (Today, Yesterday, Week, Month, All Time)
//  - Living Transaction Dossier Cards with tactile receipt slip styling
//  - Instant copyable cryptopill receipt IDs with haptic feedback
//  - Customer Contact Conduit (Direct Call & WhatsApp actions)
//  - Itemized Specimen Strips with unit ring tags
//  - Operational Shift Readiness Card (eliminating the low-density whitespace void)
//  - Surgical Refund Studio with inventory restocking
//  - High-consequence Void / Cancellation Sheet
//  - Native Thermal Print Dispatch
//

import SwiftUI
import UIKit

// MARK: - Sendable & Identifiable Conformance

extension PPPOSReceipt: @unchecked Sendable {}

extension PPPOSReceipt: Identifiable {
    public var id: String { receiptID }
}

// MARK: - WhatsApp Digital Receipt Dispatcher (Direct Chat + PDF in Clipboard)

@MainActor
enum POSReceiptWhatsAppSender {
    static let brandColor = Color(red: 37 / 255.0, green: 211 / 255.0, blue: 102 / 255.0)

    static func buildReceiptMessage(for receipt: PPPOSReceipt) -> String {
        let completed = POSCompletedReceipt(receipt: receipt)
        return buildReceiptMessage(for: completed)
    }

    static func buildReceiptMessage(for receipt: POSCompletedReceipt) -> String {
        let isRTL = Language.isRTL()
        let formattedID = receipt.formattedReceiptID
        let customerName = receipt.customerName

        if receipt.isRefunded {
            let refundAmountFormatted = POSReceiptFormat.currency(receipt.refundedAmount, code: receipt.currency)
            let reasonSnippet = (receipt.refundReason != nil && !receipt.refundReason!.isEmpty)
                ? "\n" + Language.get("POS_Receipt_RefundReason", alter: "سبب الاسترداد") + ": \(receipt.refundReason!)"
                : ""

            if isRTL {
                let greeting = !customerName.isEmpty ? "مرحباً بك يا \(customerName) في بيور بتس 🐾" : "مرحباً بكم في بيور بتس 🐾"
                let invoiceSnippet = !formattedID.isEmpty ? " (معاملة رقم: \(formattedID))" : ""
                let refundStatusDesc = receipt.isFullyRefunded ? "استرداد مالي كامل" : "استرداد مالي جزئي"

                return """
                \(greeting)
                نحيطكم علماً بأنه تم تسجيل عملية \(refundStatusDesc) بنجاح ✨

                مرفق إيصال الاسترداد المالي الإلكتروني\(invoiceSnippet) 🧾
                المبلغ المسترد: \(refundAmountFormatted)\(reasonSnippet)

                شاكرين ومقدّرين تعاملكم وثقتكم ببيور بتس 🤍

                بيور بتس | رعاية تليق بأليفك
                📞 خدمة العملاء: +974 5999 7720
                🌐 https://pure-pets.net
                """
            } else {
                let greeting = !customerName.isEmpty ? "Hello \(customerName), welcome to Pure Pets 🐾" : "Welcome to Pure Pets 🐾"
                let invoiceSnippet = !formattedID.isEmpty ? " (Transaction #\(formattedID))" : ""
                let refundStatusDesc = receipt.isFullyRefunded ? "full refund" : "partial refund"

                return """
                \(greeting)
                We would like to confirm that a \(refundStatusDesc) has been successfully processed ✨

                Attached is your official electronic refund receipt\(invoiceSnippet) 🧾
                Refunded Amount: \(refundAmountFormatted)\(reasonSnippet)

                Thank you for choosing Pure Pets! 🤍

                Pure Pets | Care Fitting Your Pet
                📞 Customer Care: +974 5999 7720
                🌐 https://pure-pets.net
                """
            }
        }

        return buildReceiptMessage(customerName: customerName, transactionID: receipt.transactionID)
    }

    static func buildReceiptMessage(customerName: String, transactionID: String) -> String {
        let isRTL = Language.isRTL()
        let formattedID = POSReceiptFormat.receiptID(transactionID)

        if isRTL {
            let greeting = !customerName.isEmpty ? "مرحباً بك يا \(customerName) في بيور بتس 🐾" : "مرحباً بكم في بيور بتس 🐾"
            let invoiceSnippet = !formattedID.isEmpty ? " (فاتورة رقم: \(formattedID))" : ""

            return """
            \(greeting)
            نسعد دائماً بخدمتكم ونتمنى لأليفكم دوام الصحة والعافية ✨

            مرفق إيصال الشراء الإلكتروني\(invoiceSnippet) 🧾
            شاكرين ومقدّرين ثقتكم واختياركم بيور بتس 🤍

            بيور بتس | رعاية تليق بأليفك
            📞 خدمة العملاء: +974 5999 7720
            🌐 https://pure-pets.net
            """
        } else {
            let greeting = !customerName.isEmpty ? "Hello \(customerName), welcome to Pure Pets 🐾" : "Welcome to Pure Pets 🐾"
            let invoiceSnippet = !formattedID.isEmpty ? " (Invoice #\(formattedID))" : ""

            return """
            \(greeting)
            It is our pleasure to serve you, and we wish your pet great health and happiness ✨

            Attached is your electronic receipt\(invoiceSnippet) 🧾
            Thank you for choosing Pure Pets! 🤍

            Pure Pets | Care Fitting Your Pet
            📞 Customer Care: +974 5999 7720
            🌐 https://pure-pets.net
            """
        }
    }

    static func sendReceipt(for receipt: PPPOSReceipt) {
        let completed = POSCompletedReceipt(receipt: receipt)
        sendReceipt(for: completed)
    }

    static func sendReceipt(for receipt: POSCompletedReceipt) {
        let message = buildReceiptMessage(for: receipt)

        // 1. Copy PDF binary data and high-res rendered image to UIPasteboard
        // NOTE: We deliberately do NOT put plain text in the pasteboard so WhatsApp exclusively pastes the high-res receipt image directly
        var pasteboardDict: [String: Any] = [:]

        if let pdfData = try? POSReceiptPDFExporter.pdfData(for: receipt) {
            pasteboardDict["com.adobe.pdf"] = pdfData
            if let image = POSReceiptPDFExporter.renderPDFPageToImage(pdfData: pdfData) {
                if let pngData = image.pngData() {
                    pasteboardDict["public.png"] = pngData
                }
                UIPasteboard.general.image = image
            }
        }

        if !pasteboardDict.isEmpty {
            UIPasteboard.general.setItems([pasteboardDict], options: [:])
        }

        // 2. Feedback
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()

        // 3. Format Phone Number
        var cleanPhone = receipt.customerPhone.filter { $0.isNumber }
        if !cleanPhone.hasPrefix("974") && cleanPhone.count == 8 {
            cleanPhone = "974" + cleanPhone
        }

        // 4. Safely encode message for URL query (escaping + & # properly)
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: "+&#")
        let encodedText = message.addingPercentEncoding(withAllowedCharacters: allowed) ?? ""

        // 5. Open direct WhatsApp chat with the customer
        if !cleanPhone.isEmpty {
            let nativeAppURL = URL(string: "whatsapp://send?phone=\(cleanPhone)&text=\(encodedText)")
            let webURL = URL(string: "https://wa.me/\(cleanPhone)?text=\(encodedText)")

            if let nativeAppURL, UIApplication.shared.canOpenURL(nativeAppURL) {
                UIApplication.shared.open(nativeAppURL)
            } else if let webURL, UIApplication.shared.canOpenURL(webURL) {
                UIApplication.shared.open(webURL)
            }
        } else {
            let nativeAppURL = URL(string: "whatsapp://send?text=\(encodedText)")
            let webURL = URL(string: "https://api.whatsapp.com/send?text=\(encodedText)")

            if let nativeAppURL, UIApplication.shared.canOpenURL(nativeAppURL) {
                UIApplication.shared.open(nativeAppURL)
            } else if let webURL, UIApplication.shared.canOpenURL(webURL) {
                UIApplication.shared.open(webURL)
            }
        }
    }
}

// MARK: - Date Horizons

enum POSDateHorizon: String, CaseIterable, Identifiable {
    case today
    case yesterday
    case week
    case month
    case all

    var id: String { rawValue }

    var localizedTitle: String {
        switch self {
        case .today:
            return Language.get("POS_Horizon_Today", alter: "اليوم")
        case .yesterday:
            return Language.get("POS_Horizon_Yesterday", alter: "أمس")
        case .week:
            return Language.get("POS_Horizon_Week", alter: "الأسبوع")
        case .month:
            return Language.get("POS_Horizon_Month", alter: "الشهر")
        case .all:
            return Language.get("POS_Horizon_All", alter: "الكل")
        }
    }

    func matches(date: Date?) -> Bool {
        guard let date else { return self == .all }
        let calendar = Calendar.current
        let now = Date()

        switch self {
        case .today:
            return calendar.isDateInToday(date)
        case .yesterday:
            return calendar.isDateInYesterday(date)
        case .week:
            guard let sevenDaysAgo = calendar.date(byAdding: .day, value: -7, to: now) else { return true }
            return date >= sevenDaysAgo && date <= now
        case .month:
            guard let thirtyDaysAgo = calendar.date(byAdding: .day, value: -30, to: now) else { return true }
            return date >= thirtyDaysAgo && date <= now
        case .all:
            return true
        }
    }
}

// MARK: - Payment Method Filters

enum POSPaymentFilter: String, CaseIterable, Identifiable {
    case all
    case cash
    case card

    var id: String { rawValue }

    var localizedTitle: String {
        switch self {
        case .all:
            return Language.get("POS_Filter_All", alter: "الكل")
        case .cash:
            return Language.get("POS_Filter_Cash", alter: "نقدي")
        case .card:
            return Language.get("POS_Filter_Card", alter: "شبكة")
        }
    }

    func matches(method: String) -> Bool {
        let lower = method.lowercased()
        switch self {
        case .all:
            return true
        case .cash:
            return lower.contains("cash")
        case .card:
            return lower.contains("card") || lower.contains("qib") || lower.contains("naps") || lower.contains("apple") || lower.contains("pos")
        }
    }
}

// MARK: - Status Filters

enum POSStatusFilter: String, CaseIterable, Identifiable {
    case all
    case completed
    case refunded
    case cancelled

    var id: String { rawValue }

    var localizedTitle: String {
        switch self {
        case .all:
            return Language.get("POS_Filter_All", alter: "الكل")
        case .completed:
            return Language.get("POS_Filter_Completed", alter: "مكتمل")
        case .refunded:
            return Language.get("POS_Filter_Refunded", alter: "مسترد")
        case .cancelled:
            return Language.get("POS_Filter_Cancelled", alter: "ملغي")
        }
    }

    func matches(receipt: PPPOSReceipt) -> Bool {
        let status = receipt.status.lowercased()
        switch self {
        case .all:
            return true
        case .completed:
            return (status == "completed" || status.isEmpty) && receipt.refundedAmount <= 0
        case .refunded:
            return status == "refunded" || status == "partially_refunded" || receipt.refundedAmount > 0
        case .cancelled:
            return status == "cancelled" || status == "voided"
        }
    }
}

// MARK: - POS History ViewModel

@MainActor
final class POSHistoryViewModel: ObservableObject {
    @Published private(set) var receipts: [PPPOSReceipt] = []
    @Published private(set) var isLoading = false
    @Published var errorMessage: String?

    // Filters
    @Published var selectedHorizon: POSDateHorizon = .today
    @Published var selectedPaymentFilter: POSPaymentFilter = .all
    @Published var selectedStatusFilter: POSStatusFilter = .all
    @Published var searchQuery: String = ""

    // Reversal Operation In-Flight States
    @Published var isSubmittingReversal: Bool = false
    @Published var reversalError: String?

    private var loadGeneration = UUID()

    func load(branchID: String?) {
        let branchID = branchID?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let generation = UUID()
        loadGeneration = generation
        receipts = []
        isLoading = true
        errorMessage = nil

        guard !branchID.isEmpty else {
            isLoading = false
            errorMessage = Language.get("BranchContext_SelectBranch_Prompt", alter: "يرجى تحديد الفرع")
            return
        }

        PPPOSService.shared().fetchPOSHistory(branchID: branchID) { [weak self] receipts, error in
            Task { @MainActor in
                guard let self, self.loadGeneration == generation,
                      BranchContextStore.shared.activeBranch?.branchID == branchID else { return }
                self.isLoading = false
                if let error {
                    self.errorMessage = error.localizedDescription
                    return
                }
                self.receipts = receipts ?? []
            }
        }
    }

    // MARK: - Horizon Filtered Set (Authoritative for Telemetry)

    var horizonReceipts: [PPPOSReceipt] {
        receipts.filter { selectedHorizon.matches(date: $0.createdAt) }
    }

    // MARK: - Filtered Receipts (Horizon + Query + Status + Payment)

    var filteredReceipts: [PPPOSReceipt] {
        let query = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return horizonReceipts.filter { receipt in
            // Payment filter
            guard selectedPaymentFilter.matches(method: receipt.paymentMethod) else { return false }

            // Status filter
            guard selectedStatusFilter.matches(receipt: receipt) else { return false }

            // Search query filter
            if !query.isEmpty {
                let idMatch = receipt.receiptID.lowercased().contains(query)
                let normIdMatch = POSReceiptFormat.receiptID(receipt.receiptID).lowercased().contains(query)
                let customerNameMatch = receipt.customerName.lowercased().contains(query)
                let customerPhoneMatch = receipt.customerPhone.lowercased().contains(query)
                let cashierMatch = (receipt.cashierName ?? "").lowercased().contains(query)
                let itemMatch = receipt.items.contains(where: { item in
                    item.name.lowercased().contains(query) ||
                    item.itemID.lowercased().contains(query) ||
                    item.unitRingTags.contains(where: { $0.lowercased().contains(query) })
                })
                return idMatch || normIdMatch || customerNameMatch || customerPhoneMatch || cashierMatch || itemMatch
            }

            return true
        }
    }

    // MARK: - Telemetry & Vital Signs (Based on selectedHorizon)

    var totalRevenue: Double {
        horizonReceipts.reduce(0.0) { sum, receipt in
            let status = receipt.status.lowercased()
            if status == "cancelled" || status == "voided" { return sum }
            let net = max(0.0, receipt.total - receipt.refundedAmount)
            return sum + net
        }
    }

    var cashRevenue: Double {
        horizonReceipts.reduce(0.0) { sum, receipt in
            let status = receipt.status.lowercased()
            if status == "cancelled" || status == "voided" { return sum }
            guard receipt.paymentMethod.lowercased().contains("cash") else { return sum }
            return sum + max(0.0, receipt.total - receipt.refundedAmount)
        }
    }

    var cardRevenue: Double {
        horizonReceipts.reduce(0.0) { sum, receipt in
            let status = receipt.status.lowercased()
            if status == "cancelled" || status == "voided" { return sum }
            guard !receipt.paymentMethod.lowercased().contains("cash") else { return sum }
            return sum + max(0.0, receipt.total - receipt.refundedAmount)
        }
    }

    var totalRefunded: Double {
        horizonReceipts.reduce(0.0) { $0 + $1.refundedAmount }
    }

    var totalTransactions: Int {
        horizonReceipts.filter {
            let st = $0.status.lowercased()
            return st != "cancelled" && st != "voided"
        }.count
    }

    var totalItemsSold: Int {
        horizonReceipts.reduce(0) { sum, receipt in
            let st = receipt.status.lowercased()
            if st == "cancelled" || st == "voided" { return sum }
            let itemsCount = receipt.items.reduce(0) { iSum, item in
                iSum + max(0, item.quantity - item.refundedQuantity)
            }
            return sum + itemsCount
        }
    }

    var averageBasket: Double {
        guard totalTransactions > 0 else { return 0.0 }
        return totalRevenue / Double(totalTransactions)
    }

    var cashRatio: Double {
        let gross = cashRevenue + cardRevenue
        guard gross > 0 else { return 0.5 }
        return cashRevenue / gross
    }

    // MARK: - Reversal Actions

    @discardableResult
    func cancelTransaction(
        receipt: PPPOSReceipt,
        reason: String
    ) async -> Bool {
        isSubmittingReversal = true
        reversalError = nil

        let result: Result<Bool, Error> = await withCheckedContinuation { continuation in
            PPPOSService.shared().cancelTransaction(
                transactionID: receipt.receiptID,
                expectedStatus: receipt.status.isEmpty ? "completed" : receipt.status,
                reason: reason
            ) { success, error in
                if let error {
                    continuation.resume(returning: .failure(error))
                } else {
                    continuation.resume(returning: .success(success))
                }
            }
        }

        isSubmittingReversal = false
        switch result {
        case .success(let ok):
            if ok {
                load(branchID: BranchContextStore.shared.activeBranch?.branchID)
            }
            return ok
        case .failure(let error):
            reversalError = Self.localizedReversalError(error)
            return false
        }
    }

    @discardableResult
    func refundTransaction(
        receipt: PPPOSReceipt,
        refundAmount: Double,
        refundItems: [[String: Any]]?,
        reason: String
    ) async -> Bool {
        isSubmittingReversal = true
        reversalError = nil

        let result: Result<Bool, Error> = await withCheckedContinuation { continuation in
            PPPOSService.shared().refundTransaction(
                transactionID: receipt.receiptID,
                refundAmount: refundAmount,
                refundItems: refundItems,
                reason: reason,
                currency: receipt.currency.isEmpty ? "QAR" : receipt.currency
            ) { success, error in
                if let error {
                    continuation.resume(returning: .failure(error))
                } else {
                    continuation.resume(returning: .success(success))
                }
            }
        }

        isSubmittingReversal = false
        switch result {
        case .success(let ok):
            if ok {
                load(branchID: BranchContextStore.shared.activeBranch?.branchID)
            }
            return ok
        case .failure(let error):
            reversalError = Self.localizedReversalError(error)
            return false
        }
    }

    // MARK: - Reversal Error Localization

    static func localizedReversalError(_ error: Error) -> String {
        let nsError = error as NSError

        let detailsDict = (nsError.userInfo["details"] as? [String: Any])
            ?? (nsError.userInfo["FIRFunctionsErrorDetailsKey"] as? [String: Any])
            ?? [:]

        let domainCode = (detailsDict["domainCode"] as? String) ?? ""
        switch domainCode {
        case "POS_TRANSACTION_STATUS_CHANGED":
            return Language.get("POS_Error_StatusChanged", alter: "تغيرت حالة المعاملة، يرجى تحديث القائمة قبل المحاولة مجدداً.")
        case "POS_INSUFFICIENT_STOCK":
            return Language.get("POS_Error_InsufficientStock", alter: "الكمية المتاحة في المخزون لا تسمح بإتمام هذه العملية.")
        default:
            break
        }

        if let msg = detailsDict["message"] as? String, !msg.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return msg
        }

        let trimmedDesc = nsError.localizedDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        let isFunctionsDomain = nsError.domain == "com.firebase.functions" || nsError.domain.contains("FIRFunctions")

        if isFunctionsDomain || trimmedDesc.uppercased() == "INTERNAL" {
            switch nsError.code {
            case 7: // Permission Denied
                return Language.get("POS_Error_PermissionDenied", alter: "ليس لديك صلاحية لإجراء استرداد أو إبطال المعاملات المالية (payments.refund).")
            case 16: // Unauthenticated
                return Language.get("POS_Error_Unauthenticated", alter: "انتهت صلاحية الجلسة، يرجى تسجيل الدخول مرة أخرى.")
            case 9: // Failed Precondition
                if trimmedDesc.contains("Non-cash") {
                    return Language.get("POS_Error_NonCash", alter: "لا يمكن استرداد العمليات غير النقدية تلقائياً؛ تتطلب تسوية عبر بوابة الدفع.")
                }
                if trimmedDesc.contains("already finalized") {
                    return Language.get("POS_Error_Finalized", alter: "تم إغلاق أو استرداد هذه المعاملة مسبقاً.")
                }
                if trimmedDesc.contains("Only completed") {
                    return Language.get("POS_Error_OnlyCompleted", alter: "يمكن استرداد المعاملات المكتملة فقط.")
                }
                return trimmedDesc
            case 13: // Internal
                return Language.get("POS_Error_InstanceUnavailable", alter: "الخادم قيد الاستجابة أو قيد بدء التشغيل السحابي. يرجى المحاولة مرة أخرى الآن.")
            case 14: // Unavailable
                return Language.get("POS_Error_Unavailable", alter: "تعذر الاتصال بالخادم، يرجى التحقق من الاتصال بالإنترنت والمحاولة مجدداً.")
            default:
                if trimmedDesc.uppercased() == "INTERNAL" {
                    return Language.get("POS_Error_InstanceUnavailable", alter: "الخادم قيد الاستجابة أو قيد بدء التشغيل السحابي. يرجى المحاولة مرة أخرى الآن.")
                }
                return trimmedDesc
            }
        }

        return trimmedDesc.isEmpty ? Language.get("Error_Unknown", alter: "حدث خطأ غير متوقع. يرجى المحاولة لاحقاً.") : trimmedDesc
    }
}

// MARK: - Sovereign POS History View

struct AdminPOSHistoryView: View {
    let session: AdminSession
    var onDismiss: (() -> Void)? = nil
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var branchStore = BranchContextStore.shared
    @StateObject private var viewModel = POSHistoryViewModel()

    // Presentation States
    @State private var selectedDossierReceipt: PPPOSReceipt? = nil
    @State private var receiptForThermalPrint: POSCompletedReceipt? = nil
    @State private var receiptNoticeForPrint: String? = nil
    @State private var receiptForRefund: PPPOSReceipt? = nil
    @State private var receiptForCancel: PPPOSReceipt? = nil
    @State private var copyToastText: String? = nil
    @State private var isShowingFastSell: Bool = false
    @State private var isSearchActive: Bool = false

    init(session: AdminSession, onDismiss: (() -> Void)? = nil) {
        self.session = session
        self.onDismiss = onDismiss
    }

    var body: some View {
        ZStack {
            AdminSurface.background.ignoresSafeArea()

            VStack(spacing: 0) {
                // 1. Sovereign Navigation Header with Vault Connectivity Beacon
                navigationHeaderView

                // 2. Compact Multi-Branch Switcher Bar
                PPAdminBranchSwitcherBar(style: .compact)
                    .padding(.horizontal, AdminSpacing.base)
                    .padding(.top, 4)
                    .padding(.bottom, 6)

                // 3. Scrollable Financial Command Ledger
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: AdminSpacing.md) {
                        // Sovereign Financial Pulse Instrument
                        financialPulseInstrument

                        // Faceted Search & Filter Intelligence Matrix
                        filterMatrixView

                        // Transaction Ledger Cards
                        ledgerSection

                        // Operational Shift Readiness Card (Eliminates low-density empty void)
                        if viewModel.filteredReceipts.count < 3 && !viewModel.isLoading {
                            shiftReadinessCard
                        }
                    }
                    .padding(.horizontal, AdminSpacing.screenMargin)
                    .padding(.vertical, AdminSpacing.sm)
                }
                .refreshable {
                    let impact = UIImpactFeedbackGenerator(style: .light)
                    impact.impactOccurred()
                    viewModel.load(branchID: branchStore.activeBranch?.branchID)
                    try? await Task.sleep(nanoseconds: 300_000_000)
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
                    .padding(.bottom, 32)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
                .zIndex(100)
            }
        }
        .environment(\.layoutDirection, Language.isRTL() ? .rightToLeft : .leftToRight)
        .onAppear {
            viewModel.load(branchID: branchStore.activeBranch?.branchID)
        }
        .onChange(of: branchStore.activeBranch?.branchID) { branchID in
            viewModel.load(branchID: branchID)
        }
        // Thermal Receipt Sheet
        .sheet(item: $receiptForThermalPrint, onDismiss: { receiptNoticeForPrint = nil }) { completedReceipt in
            POSCompletedReceiptSheet(receipt: completedReceipt, notice: receiptNoticeForPrint)
        }
        // Transaction Dossier Modal
        .sheet(item: $selectedDossierReceipt) { receipt in
            POSTransactionDossierSheet(
                receipt: receipt,
                onPrint: {
                    selectedDossierReceipt = nil
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        receiptNoticeForPrint = (receipt.refundedAmount > 0 || receipt.status.lowercased() == "refunded" || receipt.status.lowercased() == "partially_refunded")
                            ? Language.get("POS_Receipt_RefundDossier_Notice", alter: "معاملة مستردة - إيصال الاسترداد المالي المعتمد.")
                            : nil
                        receiptForThermalPrint = POSCompletedReceipt(receipt: receipt)
                    }
                },
                onRefund: {
                    selectedDossierReceipt = nil
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        receiptForRefund = receipt
                    }
                },
                onCancel: {
                    selectedDossierReceipt = nil
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        receiptForCancel = receipt
                    }
                },
                onCopied: { text in
                    showToast(text)
                }
            )
        }
        // Refund Studio Sheet
        .sheet(item: $receiptForRefund) { receipt in
            POSRefundStudioSheet(
                receipt: receipt,
                viewModel: viewModel,
                onSuccess: { refundedReceipt in
                    receiptForRefund = nil
                    showToast(Language.get("POS_Refund_Success_Title", alter: "تم الاسترداد بنجاح"))
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
                        receiptNoticeForPrint = Language.get(
                            "POS_Receipt_RefundSuccess_Notice",
                            alter: "تم تسجيل الاسترداد بنجاح في النظام. إيصال الاسترداد جاهز للطباعة والمشاركة."
                        )
                        receiptForThermalPrint = POSCompletedReceipt(receipt: refundedReceipt)
                    }
                }
            )
        }
        // Cancel / Void Confirmation Sheet
        .sheet(item: $receiptForCancel) { receipt in
            POSCancelConfirmationSheet(
                receipt: receipt,
                viewModel: viewModel,
                onSuccess: {
                    receiptForCancel = nil
                    showToast(Language.get("POS_Cancel_Success_Title", alter: "تم إلغاء المعاملة"))
                }
            )
        }
        // Fast Sell Launch Sheet
        .sheet(isPresented: $isShowingFastSell) {
            AdminPOSFastSellView(session: session) {
                isShowingFastSell = false
                viewModel.load(branchID: branchStore.activeBranch?.branchID)
            }
        }
    }

    // MARK: - Navigation Header with Vault Beacon

    private var navigationHeaderView: some View {
        VStack(alignment: .leading, spacing: 0) {
            Color.clear.frame(height: PPStatusBarHelper.statusBarHeight)

            HStack(spacing: 12) {
                // Back Button (RTL Safe)
                Button(action: {
                    let impact = UIImpactFeedbackGenerator(style: .light)
                    impact.impactOccurred()
                    if let onDismiss {
                        onDismiss()
                    } else {
                        dismiss()
                    }
                }) {
                    Image(systemName: Language.isRTL() ? "chevron.right" : "chevron.left")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(AdminSurface.primaryText)
                        .frame(width: 42, height: 42)
                        .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .strokeBorder(Color(uiColor: .ppSurfaceBorder).opacity(0.8), lineWidth: 0.8)
                        )
                        .shadow(color: Color.black.opacity(0.04), radius: 6, x: 0, y: 2)
                }
                .buttonStyle(.plain)

                // Title & Vault Connected Beacon
                VStack(alignment: .leading, spacing: 2) {
                    Text(Language.get("POS_History_Title", alter: "سجل المبيعات"))
                        .font(AdminType.title3)
                        .foregroundColor(AdminSurface.primaryText)

                    HStack(spacing: 6) {
                        Circle()
                            .fill(Color(uiColor: .systemGreen))
                            .frame(width: 7, height: 7)
                            .shadow(color: Color(uiColor: .systemGreen).opacity(0.6), radius: 4, x: 0, y: 0)

                        Text(Language.get("POS_Vault_LiveStatus", alter: "متصل بالخزينة"))
                            .font(AdminType.caption2Bold)
                            .foregroundColor(Color(uiColor: .systemGreen))

                        if let branch = branchStore.activeBranch?.localizedName() {
                            Text("•")
                                .foregroundColor(AdminSurface.secondaryText)
                            Text(branch)
                                .font(AdminType.caption2)
                                .foregroundColor(AdminSurface.secondaryText)
                                .lineLimit(1)
                        }
                    }
                }

                Spacer()

                // Search Toggle Button
                Button {
                    let impact = UIImpactFeedbackGenerator(style: .light)
                    impact.impactOccurred()
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                        isSearchActive.toggle()
                    }
                } label: {
                    Image(systemName: isSearchActive ? "magnifyingglass.circle.fill" : "magnifyingglass")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(isSearchActive ? Color(uiColor: .ppPrimary) : AdminSurface.primaryText)
                        .frame(width: 42, height: 42)
                        .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .strokeBorder(Color(uiColor: .ppSurfaceBorder).opacity(0.8), lineWidth: 0.8)
                        )
                        .shadow(color: Color.black.opacity(0.04), radius: 6, x: 0, y: 2)
                }
                .buttonStyle(.plain)

                // Refresh Button
                if viewModel.isLoading {
                    ProgressView()
                        .tint(AdminSurface.primary)
                        .scaleEffect(0.9)
                        .frame(width: 42, height: 42)
                } else {
                    Button(action: {
                        let impact = UIImpactFeedbackGenerator(style: .medium)
                        impact.impactOccurred()
                        viewModel.load(branchID: branchStore.activeBranch?.branchID)
                    }) {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundColor(AdminSurface.primaryText)
                            .frame(width: 42, height: 42)
                            .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .strokeBorder(Color(uiColor: .ppSurfaceBorder).opacity(0.8), lineWidth: 0.8)
                            )
                            .shadow(color: Color.black.opacity(0.04), radius: 6, x: 0, y: 2)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Language.get("Refresh", alter: "تحديث"))
                }
            }
            .padding(.horizontal, AdminSpacing.screenMargin)
            .padding(.top, AdminSpacing.sm)
            .padding(.bottom, AdminSpacing.xs)

            if let error = viewModel.errorMessage {
                AdminErrorBanner(
                    message: error,
                    retry: { viewModel.load(branchID: branchStore.activeBranch?.branchID) }
                )
                .padding(.horizontal, AdminSpacing.screenMargin)
                .padding(.top, 4)
            }
        }
    }

    // MARK: - Sovereign Financial Pulse Instrument

    private var financialPulseInstrument: some View {
        VStack(spacing: AdminSpacing.sm) {
            // Horizon Time Capsule Ribbon
            horizonPillSelector

            // Hero Liquidity Figure & Activity Counter
            VStack(spacing: 4) {
                HStack(spacing: 4) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 12))
                        .foregroundColor(Color(uiColor: .ppPrimary))
                    Text(Language.get("POS_Telemetry_NetRevenue", alter: "صافي الإيرادات"))
                        .font(AdminType.captionBold)
                        .foregroundColor(AdminSurface.secondaryText)
                }

                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(verbatim: viewModel.totalRevenue.englishDigits(decimals: 2))
                        .font(AdminType.largeTitle)
                        .foregroundColor(AdminSurface.primaryText)
                        .monospacedDigit()
                        .minimumScaleFactor(0.6)
                        .lineLimit(1)

                    Text(Language.get("QAR", alter: "ر.ق"))
                        .font(AdminType.headline)
                        .foregroundColor(AdminSurface.secondaryText)
                }

                HStack(spacing: 6) {
                    Circle()
                        .fill(Color(uiColor: .systemGreen))
                        .frame(width: 6, height: 6)
                    Text(String(format: Language.get("POS_Telemetry_CompletedSales_Fmt", alter: "%@ عملية معتمدة"), viewModel.totalTransactions.englishDigits))
                        .font(AdminType.caption2)
                        .foregroundColor(AdminSurface.secondaryText)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 4)

            // Dual-Channel Liquidity Splitter Spectrum Bar
            spectrumBarView

            Divider()
                .background(AdminSurface.hairline)
                .padding(.vertical, 2)

            // Micro-Telemetry Dial Ribbon
            HStack(spacing: 8) {
                telemetryDial(
                    symbol: "cart.fill",
                    color: Color(uiColor: .systemTeal),
                    title: Language.get("POS_Telemetry_AvgBasket", alter: "متوسط السلة"),
                    value: viewModel.averageBasket.englishDigits(decimals: 2) + " " + Language.get("QAR", alter: "ر.ق")
                )

                telemetryDial(
                    symbol: "shippingbox.fill",
                    color: Color(uiColor: .systemBlue),
                    title: Language.get("POS_Telemetry_UnitsSold", alter: "القطع المباعة"),
                    value: "\(viewModel.totalItemsSold.englishDigits) " + Language.get("POS_Items", alter: "قطع")
                )

                telemetryDial(
                    symbol: "arrow.uturn.backward.circle.fill",
                    color: viewModel.totalRefunded > 0 ? Color(uiColor: .systemOrange) : Color.gray,
                    title: Language.get("POS_Telemetry_Refunds", alter: "المستردات"),
                    value: viewModel.totalRefunded.englishDigits(decimals: 2) + " " + Language.get("QAR", alter: "ر.ق")
                )
            }
        }
        .padding(AdminSpacing.base)
        .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(Color(uiColor: .ppSurfaceBorder).opacity(0.8), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.04), radius: 10, x: 0, y: 4)
    }

    // MARK: - Horizon Time Capsule Ribbon

    private var horizonPillSelector: some View {
        HStack(spacing: 4) {
            ForEach(POSDateHorizon.allCases, id: \.self) { horizon in
                let isSelected = viewModel.selectedHorizon == horizon
                Button {
                    let impact = UIImpactFeedbackGenerator(style: .light)
                    impact.impactOccurred()
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                        viewModel.selectedHorizon = horizon
                    }
                } label: {
                    Text(horizon.localizedTitle)
                        .font(isSelected ? AdminType.captionBold : AdminType.caption)
                        .foregroundColor(isSelected ? .white : AdminSurface.secondaryText)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .frame(maxWidth: .infinity)
                        .background(
                            isSelected ?
                                AnyView(Capsule().fill(Color(uiColor: .ppPrimary))) :
                                AnyView(EmptyView())
                        )
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(Color(uiColor: .ppBackgroundSecondary), in: Capsule())
    }

    // MARK: - Cash vs Card Spectrum Split Bar

    private var spectrumBarView: some View {
        VStack(spacing: 8) {
            GeometryReader { geo in
                let totalWidth = geo.size.width
                let cashRatio = CGFloat(viewModel.cashRatio)
                let cashWidth = max(8, min(totalWidth - 8, totalWidth * cashRatio))
                let cardWidth = max(8, totalWidth - cashWidth)

                HStack(spacing: 3) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color(uiColor: .systemGreen))
                        .frame(width: viewModel.totalRevenue > 0 ? cashWidth : totalWidth * 0.5, height: 9)

                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color(uiColor: .systemIndigo))
                        .frame(width: viewModel.totalRevenue > 0 ? cardWidth : totalWidth * 0.5, height: 9)
                }
            }
            .frame(height: 9)

            // Interactive Split Filter Badges
            HStack {
                Button {
                    let impact = UIImpactFeedbackGenerator(style: .light)
                    impact.impactOccurred()
                    withAnimation(.spring()) {
                        viewModel.selectedPaymentFilter = (viewModel.selectedPaymentFilter == .cash) ? .all : .cash
                    }
                } label: {
                    HStack(spacing: 5) {
                        Circle()
                            .fill(Color(uiColor: .systemGreen))
                            .frame(width: 7, height: 7)
                        Text(Language.get("POS_Telemetry_Cash", alter: "نقدي"))
                            .font(AdminType.caption2)
                            .foregroundColor(AdminSurface.secondaryText)
                        Text(verbatim: viewModel.cashRevenue.englishDigits(decimals: 2) + " " + Language.get("QAR", alter: "ر.ق"))
                            .font(AdminType.captionBold)
                            .foregroundColor(viewModel.selectedPaymentFilter == .cash ? Color(uiColor: .systemGreen) : AdminSurface.primaryText)
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(
                        viewModel.selectedPaymentFilter == .cash ? Color(uiColor: .systemGreen).opacity(0.12) : Color.clear,
                        in: Capsule()
                    )
                }
                .buttonStyle(.plain)

                Spacer()

                Button {
                    let impact = UIImpactFeedbackGenerator(style: .light)
                    impact.impactOccurred()
                    withAnimation(.spring()) {
                        viewModel.selectedPaymentFilter = (viewModel.selectedPaymentFilter == .card) ? .all : .card
                    }
                } label: {
                    HStack(spacing: 5) {
                        Circle()
                            .fill(Color(uiColor: .systemIndigo))
                            .frame(width: 7, height: 7)
                        Text(Language.get("POS_Telemetry_Card", alter: "شبكة"))
                            .font(AdminType.caption2)
                            .foregroundColor(AdminSurface.secondaryText)
                        Text(verbatim: viewModel.cardRevenue.englishDigits(decimals: 2) + " " + Language.get("QAR", alter: "ر.ق"))
                            .font(AdminType.captionBold)
                            .foregroundColor(viewModel.selectedPaymentFilter == .card ? Color(uiColor: .systemIndigo) : AdminSurface.primaryText)
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(
                        viewModel.selectedPaymentFilter == .card ? Color(uiColor: .systemIndigo).opacity(0.12) : Color.clear,
                        in: Capsule()
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func telemetryDial(
        symbol: String,
        color: Color,
        title: String,
        value: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 5) {
                Image(systemName: symbol)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(color)
                Text(title)
                    .font(AdminType.caption2)
                    .foregroundColor(AdminSurface.secondaryText)
                    .lineLimit(1)
            }

            Text(verbatim: value)
                .font(PPBrandFont.bold(size: 13, relativeTo: .subheadline))
                .foregroundColor(AdminSurface.primaryText)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8)
        .background(Color(uiColor: .ppBackgroundSecondary).opacity(0.7), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    // MARK: - Faceted Filter Matrix View

    private var filterMatrixView: some View {
        VStack(spacing: AdminSpacing.xs) {
            // Expandable Search Bar
            if isSearchActive || !viewModel.searchQuery.isEmpty {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(AdminSurface.secondaryText)

                    TextField(
                        Language.get("POS_Search_Placeholder", alter: "ابحث برقم الإيصال، اسم العميل، الهاتف، أو الصنف..."),
                        text: $viewModel.searchQuery
                    )
                    .font(AdminType.body)
                    .foregroundColor(AdminSurface.primaryText)

                    if !viewModel.searchQuery.isEmpty {
                        Button {
                            viewModel.searchQuery = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 14))
                                .foregroundColor(AdminSurface.secondaryText)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(Color(uiColor: .ppSurfaceBorder).opacity(0.8), lineWidth: 0.8)
                )
                .transition(.opacity.combined(with: .move(edge: .top)))
            }

            // Filter Chips Scrollable Row
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    // Payment Filters
                    ForEach(POSPaymentFilter.allCases, id: \.self) { filter in
                        let isSelected = viewModel.selectedPaymentFilter == filter
                        Button {
                            let impact = UIImpactFeedbackGenerator(style: .light)
                            impact.impactOccurred()
                            viewModel.selectedPaymentFilter = filter
                        } label: {
                            HStack(spacing: 4) {
                                if filter == .cash {
                                    Image(systemName: "banknote.fill").font(.system(size: 10))
                                } else if filter == .card {
                                    Image(systemName: "creditcard.fill").font(.system(size: 10))
                                }
                                Text(filter.localizedTitle)
                                    .font(AdminType.caption)
                            }
                            .foregroundColor(isSelected ? .white : AdminSurface.primaryText)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(
                                isSelected ?
                                    Color(uiColor: .ppPrimary) :
                                    Color(uiColor: .ppBackgroundSecondary),
                                in: Capsule()
                            )
                        }
                        .buttonStyle(.plain)
                    }

                    Divider().frame(height: 16)

                    // Status Filters
                    ForEach(POSStatusFilter.allCases, id: \.self) { filter in
                        let isSelected = viewModel.selectedStatusFilter == filter
                        Button {
                            let impact = UIImpactFeedbackGenerator(style: .light)
                            impact.impactOccurred()
                            viewModel.selectedStatusFilter = filter
                        } label: {
                            Text(filter.localizedTitle)
                                .font(AdminType.caption)
                                .foregroundColor(isSelected ? .white : AdminSurface.primaryText)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(
                                    isSelected ?
                                        Color(uiColor: .ppPrimary) :
                                        Color(uiColor: .ppBackgroundSecondary),
                                    in: Capsule()
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 2)
            }
        }
    }

    // MARK: - Ledger Cards Section

    @ViewBuilder
    private var ledgerSection: some View {
        if viewModel.isLoading && viewModel.receipts.isEmpty {
            VStack(spacing: 12) {
                ProgressView()
                    .tint(AdminSurface.primary)
                    .scaleEffect(1.2)
                    .padding(.top, 30)
                Text(Language.get("Loading", alter: "جاري التحميل..."))
                    .font(AdminType.caption)
                    .foregroundColor(AdminSurface.secondaryText)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 30)
        } else if viewModel.filteredReceipts.isEmpty {
            AdminEmptyStateView(
                symbol: "receipt.fill",
                title: Language.get("POS_History_Empty", alter: "لا توجد معاملات بيع"),
                subtitle: viewModel.searchQuery.isEmpty ?
                    Language.get("POS_History_Empty_Sub", alter: "ستظهر المعاملات المكتملة هنا فور إتمامها") :
                    Language.get("POS_CatalogEmptyHint", alter: "غيّر عبارة البحث أو الفلاتر لعرض النتائج")
            )
            .padding(.top, 16)
        } else {
            LazyVStack(spacing: AdminSpacing.sm) {
                ForEach(viewModel.filteredReceipts, id: \.receiptID) { receipt in
                    POSTransactionCard(
                        receipt: receipt,
                        onTap: {
                            let impact = UIImpactFeedbackGenerator(style: .light)
                            impact.impactOccurred()
                            selectedDossierReceipt = receipt
                        },
                        onPrint: {
                            let impact = UIImpactFeedbackGenerator(style: .medium)
                            impact.impactOccurred()
                            receiptForThermalPrint = POSCompletedReceipt(receipt: receipt)
                        },
                        onCopyID: { id in
                            UIPasteboard.general.string = id
                            let notif = UINotificationFeedbackGenerator()
                            notif.notificationOccurred(.success)
                            showToast(Language.get("POS_Receipt_Copy_Success", alter: "تم نسخ رقم الإيصال إلى الحافظة"))
                        }
                    )
                }
            }
        }
    }

    // MARK: - Operational Shift Readiness Card (Eliminates Low-Density Whitespace Void)

    private var shiftReadinessCard: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: "storefront.fill")
                    .font(.system(size: 24))
                    .foregroundColor(Color(uiColor: .ppPrimary))
                    .frame(width: 48, height: 48)
                    .background(Color(uiColor: .ppPrimary).opacity(0.1), in: RoundedRectangle(cornerRadius: 14, style: .continuous))

                VStack(alignment: .leading, spacing: 3) {
                    Text(Language.get("POS_Shift_Summary_Title", alter: "حالة وردية المبيعات"))
                        .font(AdminType.headline)
                        .foregroundColor(AdminSurface.primaryText)

                    Text(Language.get("POS_Shift_Summary_Desc", alter: "نقطة البيع جاهزة، والأسعار وعهد المخزون محدثة ومربوطة بالفرع الحالي."))
                        .font(AdminType.caption)
                        .foregroundColor(AdminSurface.secondaryText)
                        .lineLimit(2)
                }

                Spacer()
            }

            Button {
                let impact = UIImpactFeedbackGenerator(style: .medium)
                impact.impactOccurred()
                isShowingFastSell = true
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 15, weight: .bold))
                    Text(Language.get("POS_Shift_StartSale", alter: "تسجيل عملية بيع جديدة"))
                        .font(AdminType.headline)
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 44)
                .background(Color(uiColor: .ppPrimary), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .buttonStyle(.plain)
        }
        .padding(AdminSpacing.base)
        .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Color(uiColor: .ppSurfaceBorder).opacity(0.8), lineWidth: 0.8)
        )
        .shadow(color: Color.black.opacity(0.03), radius: 6, x: 0, y: 2)
    }

    private func showToast(_ text: String) {
        withAnimation(.spring()) {
            copyToastText = text
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.2) {
            withAnimation(.easeOut) {
                if copyToastText == text {
                    copyToastText = nil
                }
            }
        }
    }
}

// MARK: - Living Transaction Dossier Card

/// Owns the local attachment until the share controller releases it, including cancellation.
private final class POSHistoryReceiptShare: Identifiable {
    let id = UUID()
    let fileURL: URL
    let message: String

    @MainActor
    init(receipt: POSCompletedReceipt) throws {
        fileURL = try POSReceiptPDFExporter.temporaryPDF(for: receipt)
        message = String(
            format: Language.get("POS_History_ReceiptMessage", alter: "مرحباً،\nمرفق إيصال معاملتكم رقم %@ من بيور بتس 🐾\nشكراً لتعاملكم معنا."),
            receipt.formattedReceiptID
        )
    }

    deinit {
        try? FileManager.default.removeItem(at: fileURL)
    }
}

private struct POSHistoryReceiptShareSheet: UIViewControllerRepresentable {
    let share: POSHistoryReceiptShare
    let onFailure: () -> Void
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UIActivityViewController {
        // WhatsApp's URL scheme accepts text, not local attachments. The native share
        // extension receives both items and lets the operator choose the recipient.
        let controller = UIActivityViewController(
            activityItems: [share.fileURL, share.message],
            applicationActivities: nil
        )
        controller.completionWithItemsHandler = { _, _, _, error in
            Task { @MainActor in
                dismiss()
                if error != nil { onFailure() }
            }
        }
        return controller
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

private struct POSTransactionCard: View {
    let receipt: PPPOSReceipt
    let onTap: () -> Void
    let onPrint: () -> Void
    let onCopyID: (String) -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var receiptShare: POSHistoryReceiptShare?
    @State private var feedbackMessage: String?
    @State private var isPreparingReceipt = false
    @State private var shareFailed = false

    var body: some View {
        VStack(spacing: AdminSpacing.sm) {
            receiptContent
            contactActions
        }
        .padding(AdminSpacing.base)
        .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Color(uiColor: .ppSurfaceBorder).opacity(0.8), lineWidth: 0.8)
        )
        .shadow(color: Color.black.opacity(0.03), radius: 6, x: 0, y: 2)
        .sheet(item: $receiptShare, onDismiss: {
            if shareFailed {
                shareFailed = false
                feedbackMessage = Language.get("POS_History_ShareFailed", alter: "تعذرت مشاركة الإيصال. حاول مرة أخرى.")
            }
        }) { share in
            POSHistoryReceiptShareSheet(share: share) {
                shareFailed = true
            }
        }
        .alert(
            Language.get("POS_History_ContactFailed", alter: "تعذر إكمال الإجراء"),
            isPresented: Binding(
                get: { feedbackMessage != nil },
                set: { if !$0 { feedbackMessage = nil } }
            )
        ) {
            Button(Language.get("OK", alter: "موافق"), role: .cancel) {}
        } message: {
            Text(feedbackMessage ?? "")
        }
    }

    private var receiptContent: some View {
        Button(action: onTap) {
            VStack(spacing: AdminSpacing.sm) {
                // 1. Top Header: Cryptopill Slug + Timestamp + Status Badge
                HStack(alignment: .center) {
                    // Monospaced Cryptopill Slug with Tap-to-Copy
                    Button {
                        onCopyID(receipt.receiptID)
                    } label: {
                        HStack(spacing: 4) {
                            Text(verbatim: POSReceiptFormat.receiptID(receipt.receiptID))
                                .font(.system(size: 13, weight: .bold, design: .monospaced))
                                .foregroundColor(Color(uiColor: .ppPrimary))

                            Image(systemName: "doc.on.doc")
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundColor(AdminSurface.secondaryText)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color(uiColor: .ppPrimary).opacity(0.08), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                    }
                    .buttonStyle(.plain)

                    Spacer()

                    // Timestamp
                    if let date = receipt.createdAt {
                        Text(formattedDate(date))
                            .font(AdminType.caption2)
                            .foregroundColor(AdminSurface.secondaryText)
                    }

                    // Status Badge
                    statusBadge
                }

                // 2. Customer identity. Contact actions remain available below every receipt.
                if !receipt.customerName.isEmpty || !receipt.customerPhone.isEmpty {
                    HStack(spacing: 8) {
                        Image(systemName: "person.crop.circle.fill")
                            .font(.system(size: 13))
                            .foregroundColor(Color(uiColor: .ppPrimary))

                        Text(receipt.customerName.isEmpty ? receipt.customerPhone : receipt.customerName)
                            .font(AdminType.captionBold)
                            .foregroundColor(AdminSurface.primaryText)
                            .lineLimit(1)

                        Spacer()
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color(uiColor: .ppBackgroundSecondary).opacity(0.5), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                }

                // 3. Purchased Items Specimen Strip
                if !receipt.items.isEmpty {
                    HStack(spacing: 6) {
                        Image(systemName: "bag.fill")
                            .font(.system(size: 11))
                            .foregroundColor(AdminSurface.secondaryText)

                        Text(itemsPreviewText)
                            .font(AdminType.caption)
                            .foregroundColor(AdminSurface.secondaryText)
                            .lineLimit(1)

                        Spacer()

                        if let cashier = receipt.cashierName, !cashier.isEmpty {
                            Text(verbatim: String(format: Language.get("POS_Card_Cashier", alter: "الكاشير: %@"), cashier))
                                .font(AdminType.caption2)
                                .foregroundColor(AdminSurface.secondaryText)
                        }
                    }
                }

                Divider().background(AdminSurface.hairline)

                // 4. Bottom Line: Payment Badge + Items Count + Total + Thermal Print
                HStack(alignment: .center, spacing: 8) {
                    paymentMethodBadge

                    Label(
                        String(format: Language.get("POS_Card_Items_Count", alter: "%@ عناصر"), receipt.items.count.englishDigits),
                        systemImage: "shippingbox.fill"
                    )
                    .font(AdminType.caption2)
                    .foregroundColor(AdminSurface.secondaryText)

                    Spacer()

                    // Grand Total Display
                    VStack(alignment: .trailing, spacing: 1) {
                        Text(verbatim: receipt.total.englishDigits(decimals: 2) + " " + Language.get("QAR", alter: "ر.ق"))
                            .font(PPBrandFont.bold(size: 19, relativeTo: .subheadline))
                            .foregroundColor(receiptIsCancelled ? AdminSurface.secondaryText : AdminSurface.primaryText)
                            .monospacedDigit()

                        if receipt.refundedAmount > 0 {
                            Text(verbatim: "−" + receipt.refundedAmount.englishDigits(decimals: 2) + " " + Language.get("POS_Status_Refunded", alter: "مسترد"))
                                .font(AdminType.caption2Bold)
                                .foregroundColor(Color(uiColor: .systemOrange))
                        }
                    }

                    // Direct Print Button
                    Button(action: onPrint) {
                        Image(systemName: "printer.fill")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(AdminSurface.primaryText)
                            .frame(width: 34, height: 34)
                            .background(Color(uiColor: .ppBackgroundSecondary), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Language.get("POS_Action_PrintReceipt", alter: "طباعة"))
                }
            }
        }
        .buttonStyle(.plain)
    }

    private var contactActions: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(spacing: 8))
            : AnyLayout(HStackLayout(spacing: 8))

        return layout {
            Button(action: shareReceipt) {
                HStack(spacing: 7) {
                    if isPreparingReceipt {
                        ProgressView().tint(AdminSurface.primaryText)
                    } else {
                        Image("whatsapp")
                            .renderingMode(.template)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 18, height: 18)
                            .accessibilityHidden(true)
                    }
                    Text(Language.get("WhatsApp", alter: "واتساب"))
                        .font(AdminType.captionBold)
                }
                .foregroundStyle(AdminSurface.primaryText)
                .frame(maxWidth: .infinity, minHeight: 44)
                .background(POSReceiptWhatsAppSender.brandColor.opacity(0.14), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(isPreparingReceipt || receiptShare != nil)
            .accessibilityLabel(Language.get("POS_Action_WhatsAppReceipt", alter: "إرسال الإيصال عبر واتساب"))
            .accessibilityHint(Language.get("POS_History_WhatsAppShareHint", alter: "اختر واتساب ثم العميل لمشاركة الرسالة وملف الإيصال."))

            Button(action: callCustomer) {
                Label(
                    customerCallURL == nil
                        ? Language.get("POS_History_CallNoPhone", alter: "اتصال · لا يوجد رقم")
                        : Language.get("Call", alter: "اتصال"),
                    systemImage: "phone.fill"
                )
                    .font(AdminType.captionBold)
                    .foregroundStyle(customerCallURL == nil ? AdminSurface.secondaryText : AdminSurface.primaryText)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .background(Color(uiColor: .ppBackgroundSecondary), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(customerCallURL == nil)
            .accessibilityLabel(Language.get("POS_Customer_Call", alter: "اتصال هاتفي"))
            .accessibilityValue(customerCallURL == nil
                ? Language.get("POS_History_NoCustomerPhone", alter: "لا يوجد رقم هاتف صالح لهذه المعاملة")
                : receipt.customerPhone)
        }
    }

    private var customerCallURL: URL? {
        let rawPhone = receipt.customerPhone.trimmingCharacters(in: .whitespacesAndNewlines)
        // Reject dial commands/extensions; normalize Arabic and Persian decimal digits.
        let digits = "0123456789٠١٢٣٤٥٦٧٨٩۰۱۲۳۴۵۶۷۸۹"
        guard rawPhone.allSatisfy({ digits.contains($0) || "+()- .".contains($0) }) else { return nil }
        var number = rawPhone.compactMap { character -> String? in
            guard digits.contains(character), let digit = character.wholeNumberValue else { return nil }
            return String(digit)
        }.joined()
        guard rawPhone.filter({ $0 == "+" }).count <= 1,
              !rawPhone.contains("+") || rawPhone.hasPrefix("+") else { return nil }
        let hasInternationalPrefix = rawPhone.hasPrefix("+") || number.hasPrefix("00")
        if number.hasPrefix("00") { number.removeFirst(2) }
        if !hasInternationalPrefix && number.count == 8 { number = "974" + number }
        guard (8...15).contains(number.count), number.first != "0" else { return nil }
        return URL(string: "tel:+\(number)")
    }

    private func callCustomer() {
        guard let url = customerCallURL else { return }
        UIApplication.shared.open(url, options: [:]) { opened in
            if !opened {
                Task { @MainActor in
                    feedbackMessage = Language.get("POS_History_CallFailed", alter: "تعذر بدء المكالمة من هذا الجهاز.")
                }
            }
        }
    }

    private func shareReceipt() {
        guard !isPreparingReceipt, receiptShare == nil else { return }
        guard let whatsAppURL = URL(string: "whatsapp://send"),
              UIApplication.shared.canOpenURL(whatsAppURL) else {
            feedbackMessage = Language.get("POS_History_WhatsAppUnavailable", alter: "ثبّت واتساب على هذا الجهاز لمشاركة الإيصال.")
            return
        }
        shareFailed = false
        isPreparingReceipt = true
        Task { @MainActor in
            await Task.yield()
            defer { isPreparingReceipt = false }
            do {
                receiptShare = try POSHistoryReceiptShare(receipt: POSCompletedReceipt(receipt: receipt))
            } catch {
                feedbackMessage = Language.get("POS_Receipt_ExportFailed", alter: "تعذر إنشاء ملف الإيصال. حاول مرة أخرى.")
            }
        }
    }

    private var receiptIsCancelled: Bool {
        let st = receipt.status.lowercased()
        return st == "cancelled" || st == "voided"
    }

    private var itemsPreviewText: String {
        let names = receipt.items.prefix(2).map { "\($0.name) × \($0.quantity.englishDigits)" }
        let joined = names.joined(separator: " • ")
        if receipt.items.count > 2 {
            let extra = (receipt.items.count - 2).englishDigits
            return "\(joined) +\(extra)"
        }
        return joined
    }

    private var statusBadge: some View {
        let status = receipt.status.lowercased()
        if status == "cancelled" || status == "voided" {
            return AdminStatusBadge(
                text: Language.get("POS_Status_Cancelled", alter: "ملغي"),
                status: .error
            )
        } else if status == "refunded" {
            return AdminStatusBadge(
                text: Language.get("POS_Status_Refunded", alter: "مسترد بالكامل"),
                status: .warning
            )
        } else if status == "partially_refunded" || receipt.refundedAmount > 0 {
            return AdminStatusBadge(
                text: Language.get("POS_Status_PartiallyRefunded", alter: "مسترد جزئياً"),
                status: .warning
            )
        } else {
            return AdminStatusBadge(
                text: Language.get("POS_Status_Completed", alter: "مكتمل"),
                status: .success
            )
        }
    }

    private var paymentMethodBadge: some View {
        let method = receipt.paymentMethod.lowercased()
        let text = POSReceiptFormat.paymentMethod(receipt.paymentMethod)
        let status: AdminStatusBadge.Status
        if method.contains("cash") {
            status = .success
        } else if method.contains("card") || method.contains("qib") || method.contains("pos") {
            status = .info
        } else if method.contains("cheque") || method.contains("fawry") {
            status = .warning
        } else {
            status = .neutral
        }
        return AdminStatusBadge(text: text, status: status)
    }

    private func formattedDate(_ date: Date) -> String {
        let calendar = Calendar.current
        let formatter = DateFormatter()
        if calendar.isDateInToday(date) {
            formatter.timeStyle = .short
            formatter.locale = Locale(identifier: Language.isRTL() ? "ar_QA" : "en_US")
            return formatter.string(from: date)
        } else {
            formatter.dateStyle = .short
            formatter.timeStyle = .short
            formatter.locale = Locale(identifier: Language.isRTL() ? "ar_QA" : "en_US")
            return formatter.string(from: date)
        }
    }
}

// MARK: - Transaction Dossier Sheet (Full Inspection & Operational Workflows)

struct POSTransactionDossierSheet: View {
    let receipt: PPPOSReceipt
    let onPrint: () -> Void
    let onRefund: () -> Void
    let onCancel: () -> Void
    let onCopied: (String) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            AdminSurface.background.ignoresSafeArea()

            VStack(spacing: 0) {
                // Header
                dossierHeader

                Divider().background(AdminSurface.hairline)

                // Scrollable Content
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: AdminSpacing.md) {
                        // Cancellation or Refund Banner
                        if isCancelled {
                            cancellationBanner
                        } else if isRefunded {
                            refundBanner
                        }

                        // Customer Contact Conduit
                        if !receipt.customerName.isEmpty || !receipt.customerPhone.isEmpty {
                            customerConduitCard
                        }

                        // Itemized Products Section
                        itemizedProductsSection

                        // Financial Breakdown Section
                        financialBreakdownSection

                        // Operator Metadata Section
                        metadataSection
                    }
                    .padding(AdminSpacing.screenMargin)
                }

                // Command Action Bar
                commandActionBar
            }
        }
        .environment(\.layoutDirection, Language.isRTL() ? .rightToLeft : .leftToRight)
    }

    private var isCancelled: Bool {
        let st = receipt.status.lowercased()
        return st == "cancelled" || st == "voided"
    }

    private var effectiveRefundedAmount: Double {
        if receipt.refundedAmount > 0 { return receipt.refundedAmount }
        let sum = receipt.items.reduce(0.0) { $0 + (Double($1.refundedQuantity) * $1.price) }
        return sum
    }

    private var isRefunded: Bool {
        let st = receipt.status.lowercased()
        return st == "refunded" || st == "partially_refunded" || effectiveRefundedAmount > 0
    }

    private var isFullyRefunded: Bool {
        let st = receipt.status.lowercased()
        if st == "refunded" { return true }
        if effectiveRefundedAmount >= receipt.total && receipt.total > 0 { return true }
        return !receipt.items.isEmpty && receipt.items.allSatisfy { $0.refundedQuantity >= $0.quantity }
    }

    private var dossierHeader: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(Language.get("POS_Dossier_Title", alter: "ملف المعاملة المالية"))
                    .font(AdminType.headline)
                    .foregroundColor(AdminSurface.primaryText)

                HStack(spacing: 6) {
                    Text(verbatim: POSReceiptFormat.receiptID(receipt.receiptID))
                        .font(.system(size: 13, weight: .bold, design: .monospaced))
                        .foregroundColor(Color(uiColor: .ppPrimary))

                    if let branch = receipt.branchName ?? BranchContextStore.shared.activeBranch?.localizedName() {
                        Text("•")
                            .foregroundColor(AdminSurface.secondaryText)
                        Text(branch)
                            .font(AdminType.caption2)
                            .foregroundColor(AdminSurface.secondaryText)
                    }
                }
            }

            Spacer()

            AdminSquircleCloseButton {
                dismiss()
            }
        }
        .padding(.horizontal, AdminSpacing.screenMargin)
        .padding(.vertical, AdminSpacing.md)
    }

    // MARK: - Cancellation & Refund Banners

    private var cancellationBanner: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "xmark.octagon.fill")
                .font(.system(size: 20))
                .foregroundColor(Color(uiColor: .systemRed))

            VStack(alignment: .leading, spacing: 4) {
                Text(Language.get("POS_Status_Cancelled", alter: "معاملة ملغاة ومبطلة"))
                    .font(AdminType.headline)
                    .foregroundColor(Color(uiColor: .systemRed))

                if let reason = receipt.cancellationReason, !reason.isEmpty {
                    Text(verbatim: reason)
                        .font(AdminType.caption)
                        .foregroundColor(AdminSurface.primaryText)
                }

                if let by = receipt.cancelledBy, !by.isEmpty {
                    Text(verbatim: "بواسطة: \(by)")
                        .font(AdminType.caption2)
                        .foregroundColor(AdminSurface.secondaryText)
                }
            }
            Spacer()
        }
        .padding(14)
        .background(Color(uiColor: .systemRed).opacity(0.08), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color(uiColor: .systemRed).opacity(0.3), lineWidth: 1)
        )
    }

    private var refundBanner: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: isFullyRefunded ? "checkmark.seal.fill" : "arrow.uturn.backward.circle.fill")
                .font(.system(size: 22))
                .foregroundColor(isFullyRefunded ? Color(uiColor: .systemPurple) : Color(uiColor: .systemOrange))

            VStack(alignment: .leading, spacing: 4) {
                Text(isFullyRefunded ? Language.get("POS_Status_Refunded", alter: "مستردة بالكامل") : Language.get("POS_Status_PartiallyRefunded", alter: "مستردة جزئياً"))
                    .font(AdminType.headline)
                    .foregroundColor(isFullyRefunded ? Color(uiColor: .systemPurple) : Color(uiColor: .systemOrange))

                Text(verbatim: "المبلغ المسترد: \(effectiveRefundedAmount.englishDigits(decimals: 2)) \(Language.get("QAR", alter: "ر.ق"))")
                    .font(AdminType.captionBold)
                    .foregroundColor(AdminSurface.primaryText)

                if let reason = receipt.refundReason, !reason.isEmpty {
                    Text(verbatim: "السبب: \(reason)")
                        .font(AdminType.caption2)
                        .foregroundColor(AdminSurface.secondaryText)
                }
            }
            Spacer()
        }
        .padding(14)
        .background(
            (isFullyRefunded ? Color(uiColor: .systemPurple) : Color(uiColor: .systemOrange)).opacity(0.08),
            in: RoundedRectangle(cornerRadius: 14, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(
                    (isFullyRefunded ? Color(uiColor: .systemPurple) : Color(uiColor: .systemOrange)).opacity(0.3),
                    lineWidth: 1
                )
        )
    }

    // MARK: - Customer Conduit Card

    private var customerConduitCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(Language.get("POS_Dossier_Customer_Section", alter: "بيانات العميل"))
                .font(AdminType.captionBold)
                .foregroundColor(AdminSurface.secondaryText)

            HStack(spacing: 12) {
                Image(systemName: "person.circle.fill")
                    .font(.system(size: 34))
                    .foregroundColor(Color(uiColor: .ppPrimary))

                VStack(alignment: .leading, spacing: 2) {
                    if !receipt.customerName.isEmpty {
                        Text(receipt.customerName)
                            .font(AdminType.headline)
                            .foregroundColor(AdminSurface.primaryText)
                    }
                    if !receipt.customerPhone.isEmpty {
                        Text(verbatim: receipt.customerPhone)
                            .font(AdminType.caption.monospaced())
                            .foregroundColor(AdminSurface.secondaryText)
                    }
                }

                Spacer()

                // Call & WhatsApp Actions
                if !receipt.customerPhone.isEmpty {
                    HStack(spacing: 8) {
                        Button {
                            let clean = receipt.customerPhone.filter { $0.isNumber || $0 == "+" }
                            if let url = URL(string: "tel://\(clean)"), UIApplication.shared.canOpenURL(url) {
                                UIApplication.shared.open(url)
                            }
                        } label: {
                            Image(systemName: "phone.circle.fill")
                                .font(.system(size: 30))
                                .foregroundColor(Color(uiColor: .systemGreen))
                        }
                        .buttonStyle(.plain)

                        Button {
                            POSReceiptWhatsAppSender.sendReceipt(for: receipt)
                        } label: {
                            ZStack {
                                Circle()
                                    .fill(POSReceiptWhatsAppSender.brandColor)
                                    .frame(width: 30, height: 30)
                                Image("whatsapp")
                                    .renderingMode(.template)
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: 17, height: 17)
                                    .foregroundColor(.white)
                            }
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(Language.get("POS_Action_WhatsAppReceipt", alter: "إرسال الإيصال عبر واتساب"))
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

    // MARK: - Itemized Products Section

    private var itemizedProductsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(Language.get("POS_Dossier_Items_Section", alter: "العناصر المشتراة"))
                .font(AdminType.captionBold)
                .foregroundColor(AdminSurface.secondaryText)

            VStack(spacing: 8) {
                ForEach(0..<receipt.items.count, id: \.self) { idx in
                    let item = receipt.items[idx]
                    HStack(alignment: .top, spacing: 10) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(item.name.isEmpty ? Language.get("POS_Receipt_UnnamedItem", alter: "عنصر") : item.name)
                                .font(AdminType.body)
                                .foregroundColor(AdminSurface.primaryText)

                            HStack(spacing: 6) {
                                Text(verbatim: "\(item.quantity.englishDigits) × \(item.price.englishDigits(decimals: 2)) \(Language.get("QAR", alter: "ر.ق"))")
                                    .font(AdminType.caption)
                                    .foregroundColor(AdminSurface.secondaryText)

                                if item.refundedQuantity > 0 {
                                    Text(verbatim: "(\(item.refundedQuantity.englishDigits) مسترد)")
                                        .font(.system(size: 10, weight: .bold))
                                        .foregroundColor(Color(uiColor: .systemOrange))
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(Color(uiColor: .systemOrange).opacity(0.1), in: Capsule())
                                }
                            }

                            // Unit Ring Tags
                            if !item.unitRingTags.isEmpty {
                                HStack(spacing: 4) {
                                    ForEach(item.unitRingTags, id: \.self) { tag in
                                        Text(verbatim: "#\(tag)")
                                            .font(.system(size: 10, weight: .semibold, design: .monospaced))
                                            .foregroundColor(AdminSurface.secondaryText)
                                            .padding(.horizontal, 5)
                                            .padding(.vertical, 2)
                                            .background(Color(uiColor: .ppBackgroundSecondary), in: RoundedRectangle(cornerRadius: 4))
                                    }
                                }
                            }
                        }

                        Spacer()

                        let lineTotal = item.lineTotal > 0 ? item.lineTotal : (item.price * Double(item.quantity))
                        Text(verbatim: lineTotal.englishDigits(decimals: 2) + " " + Language.get("QAR", alter: "ر.ق"))
                            .font(AdminType.headline)
                            .foregroundColor(AdminSurface.primaryText)
                            .monospacedDigit()
                    }
                    .padding(.vertical, 4)

                    if idx < receipt.items.count - 1 {
                        Divider().background(AdminSurface.hairline)
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

    // MARK: - Financial Breakdown Section

    private var financialBreakdownSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(Language.get("POS_Dossier_Financial_Section", alter: "التفاصيل المالية"))
                .font(AdminType.captionBold)
                .foregroundColor(AdminSurface.secondaryText)

            VStack(spacing: 10) {
                summaryRow(
                    label: Language.get("POS_Subtotal", alter: "المجموع الفرعي"),
                    value: (receipt.subtotal > 0 ? receipt.subtotal : receipt.total + receipt.discount).englishDigits(decimals: 2) + " " + Language.get("QAR", alter: "ر.ق")
                )

                if receipt.discount > 0 {
                    summaryRow(
                        label: Language.get("POS_Discount", alter: "الخصم"),
                        value: "−" + receipt.discount.englishDigits(decimals: 2) + " " + Language.get("QAR", alter: "ر.ق"),
                        valueColor: Color(uiColor: .systemGreen)
                    )
                }

                if receipt.paymentMethod.lowercased().contains("cash") {
                    if receipt.cashReceived > 0 {
                        summaryRow(
                            label: Language.get("POS_CashReceived", alter: "المستلم نقداً"),
                            value: receipt.cashReceived.englishDigits(decimals: 2) + " " + Language.get("QAR", alter: "ر.ق")
                        )
                    }
                    if receipt.changeDue > 0 {
                        summaryRow(
                            label: Language.get("POS_ChangeDue", alter: "المتبقي للعميل"),
                            value: receipt.changeDue.englishDigits(decimals: 2) + " " + Language.get("QAR", alter: "ر.ق"),
                            valueColor: Color(uiColor: .systemBlue)
                        )
                    }
                }

                Divider().background(AdminSurface.hairline)

                // Grand Total
                HStack {
                    Text(Language.get("POS_GrandTotal", alter: "الإجمالي النهائي"))
                        .font(AdminType.headline)
                        .foregroundColor(AdminSurface.primaryText)

                    Spacer()

                    Text(verbatim: receipt.total.englishDigits(decimals: 2) + " " + Language.get("QAR", alter: "ر.ق"))
                        .font(PPBrandFont.bold(size: 22, relativeTo: .title2))
                        .foregroundColor(AdminSurface.primaryText)
                        .monospacedDigit()
                }

                if effectiveRefundedAmount > 0 {
                    HStack {
                        Text(Language.get("POS_Telemetry_Refunds", alter: "إجمالي المسترد"))
                            .font(AdminType.captionBold)
                            .foregroundColor(Color(uiColor: .systemOrange))

                        Spacer()

                        Text(verbatim: "−" + effectiveRefundedAmount.englishDigits(decimals: 2) + " " + Language.get("QAR", alter: "ر.ق"))
                            .font(AdminType.headline)
                            .foregroundColor(Color(uiColor: .systemOrange))
                            .monospacedDigit()
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

    private func summaryRow(label: String, value: String, valueColor: Color = AdminSurface.primaryText) -> some View {
        HStack {
            Text(label)
                .font(AdminType.body)
                .foregroundColor(AdminSurface.secondaryText)
            Spacer()
            Text(verbatim: value)
                .font(AdminType.body)
                .foregroundColor(valueColor)
                .monospacedDigit()
        }
    }

    // MARK: - Metadata Section

    private var metadataSection: some View {
        VStack(spacing: 8) {
            HStack {
                Text(Language.get("POS_Dossier_Date", alter: "وقت المعاملة"))
                    .font(AdminType.caption)
                    .foregroundColor(AdminSurface.secondaryText)
                Spacer()
                if let date = receipt.createdAt {
                    Text(formattedFullDate(date))
                        .font(AdminType.captionBold)
                        .foregroundColor(AdminSurface.primaryText)
                }
            }

            if let cashier = receipt.cashierName, !cashier.isEmpty {
                HStack {
                    Text("كاشير العملية")
                        .font(AdminType.caption)
                        .foregroundColor(AdminSurface.secondaryText)
                    Spacer()
                    Text(cashier)
                        .font(AdminType.captionBold)
                        .foregroundColor(AdminSurface.primaryText)
                }
            }

            HStack {
                Text("معرّف المعاملة الخادمي")
                    .font(AdminType.caption)
                    .foregroundColor(AdminSurface.secondaryText)
                Spacer()
                Button {
                    UIPasteboard.general.string = receipt.receiptID
                    onCopied(receipt.receiptID)
                } label: {
                    HStack(spacing: 4) {
                        Text(verbatim: String(receipt.receiptID.prefix(16)) + "...")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(Color(uiColor: .ppPrimary))
                        Image(systemName: "doc.on.doc")
                            .font(.system(size: 10))
                            .foregroundColor(AdminSurface.secondaryText)
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(14)
        .background(Color(uiColor: .ppBackgroundSecondary).opacity(0.5), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    // MARK: - Command Action Bar

    private var commandActionBar: some View {
        VStack(spacing: 10) {
            Divider().background(AdminSurface.hairline)

            HStack(spacing: 10) {
                // Thermal Receipt Button
                Button(action: onPrint) {
                    HStack(spacing: 6) {
                        Image(systemName: "printer.fill")
                            .font(.system(size: 14, weight: .bold))
                        Text(isRefunded ? Language.get("POS_Action_PrintRefundReceipt", alter: "طباعة إيصال الاسترداد") : Language.get("POS_Action_PrintReceipt", alter: "طباعة الإيصال"))
                            .font(AdminType.captionBold)
                    }
                    .foregroundColor(AdminSurface.primaryText)
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
                    .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(Color(uiColor: .ppSurfaceBorder), lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)

                // Refund Button
                Button(action: onRefund) {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.uturn.backward.circle.fill")
                            .font(.system(size: 14, weight: .bold))
                        Text(Language.get("POS_Action_Refund", alter: "استرداد"))
                            .font(AdminType.captionBold)
                    }
                    .foregroundColor(isCancelled || isFullyRefunded ? AdminSurface.secondaryText.opacity(0.5) : Color(uiColor: .systemOrange))
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
                    .background(Color(uiColor: .systemOrange).opacity(0.1), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(isCancelled || isFullyRefunded)

                // Cancel / Void Button
                Button(action: onCancel) {
                    HStack(spacing: 6) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 14, weight: .bold))
                        Text(Language.get("POS_Action_Cancel", alter: "إلغاء"))
                            .font(AdminType.captionBold)
                    }
                    .foregroundColor(isCancelled || isRefunded ? AdminSurface.secondaryText.opacity(0.5) : Color(uiColor: .systemRed))
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
                    .background(Color(uiColor: .systemRed).opacity(0.1), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(isCancelled || isRefunded)
            }
            .padding(.horizontal, AdminSpacing.screenMargin)
            .padding(.bottom, 14)
        }
        .background(AdminSurface.surface)
    }

    private func formattedFullDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .medium
        formatter.locale = Locale(identifier: Language.isRTL() ? "ar_QA" : "en_US")
        return formatter.string(from: date)
    }
}

// MARK: - POS Refund Studio Sheet

struct POSRefundStudioSheet: View {
    let receipt: PPPOSReceipt
    @ObservedObject var viewModel: POSHistoryViewModel
    let onSuccess: (PPPOSReceipt) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var isFullRefund: Bool = true
    @State private var itemQuantities: [String: Int] = [:]
    @State private var itemConditions: [String: String] = [:]
    @State private var selectedReason: String = ""
    @State private var customReason: String = ""

    private struct ReturnConditionOption: Identifiable {
        let id: String
        let titleKey: String
        let defaultTitle: String
        let icon: String
        let tint: Color
        let defaultDisposition: String
    }

    private let returnConditionOptions: [ReturnConditionOption] = [
        ReturnConditionOption(
            id: "sellable",
            titleKey: "pos_refund_condition_sellable",
            defaultTitle: "سليم (صالح للبيع)",
            icon: "checkmark.seal.fill",
            tint: Color(uiColor: .systemGreen),
            defaultDisposition: "return_to_stock"
        ),
        ReturnConditionOption(
            id: "damaged",
            titleKey: "pos_refund_condition_damaged",
            defaultTitle: "تالف (عزل للإتلاف)",
            icon: "exclamationmark.triangle.fill",
            tint: Color(uiColor: .systemOrange),
            defaultDisposition: "hold_damaged"
        ),
        ReturnConditionOption(
            id: "expired",
            titleKey: "pos_refund_condition_expired",
            defaultTitle: "منتهي الصلاحية",
            icon: "clock.badge.xmark.fill",
            tint: Color(uiColor: .systemRed),
            defaultDisposition: "write_off"
        ),
        ReturnConditionOption(
            id: "quarantine",
            titleKey: "pos_refund_condition_quarantine",
            defaultTitle: "حجر (بحاجة لفحص)",
            icon: "cross.case.fill",
            tint: Color(uiColor: .systemPurple),
            defaultDisposition: "hold_for_inspection"
        )
    ]

    private let reasonPresets: [String] = [
        Language.get("POS_Refund_Reason_Chip_Customer", alter: "رغبة العميل"),
        Language.get("POS_Refund_Reason_Chip_Defect", alter: "عيب مصنعي"),
        Language.get("POS_Refund_Reason_Chip_Error", alter: "خطأ في الفاتورة"),
        Language.get("POS_Refund_Reason_Chip_Damaged", alter: "صنف تالف")
    ]

    var body: some View {
        ZStack {
            AdminSurface.background.ignoresSafeArea()

            VStack(spacing: 0) {
                // Header
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(Language.get("POS_RefundStudio_Title", alter: "استوديو الاسترداد المالي"))
                            .font(AdminType.headline)
                            .foregroundColor(AdminSurface.primaryText)

                        Text(Language.get("POS_RefundStudio_Sub", alter: "إرجاع الكميات للمخزون واسترداد المبلغ"))
                            .font(AdminType.caption)
                            .foregroundColor(AdminSurface.secondaryText)
                    }

                    Spacer()

                    AdminSquircleCloseButton {
                        dismiss()
                    }
                }
                .padding(.horizontal, AdminSpacing.screenMargin)
                .padding(.vertical, AdminSpacing.md)

                Divider().background(AdminSurface.hairline)

                // Scrollable Body
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: AdminSpacing.md) {
                        // Error Banner
                        if let error = viewModel.reversalError {
                            AdminErrorBanner(message: error)
                        }

                        // Mode Selector: Full Refund vs Partial
                        HStack(spacing: 10) {
                            modeButton(
                                title: Language.get("POS_Refund_Full_Action", alter: "استرداد كامل"),
                                isSelected: isFullRefund
                            ) {
                                isFullRefund = true
                                initializeQuantities()
                            }

                            modeButton(
                                title: Language.get("POS_Refund_Select_Items", alter: "تحديد أصناف"),
                                isSelected: !isFullRefund
                            ) {
                                isFullRefund = false
                            }
                        }

                        // Item Selection & Condition Section (Always displayed)
                        itemSelectionSection

                        // Restock & Disposition Notice
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: "shippingbox.and.arrow.backward.fill")
                                .font(.system(size: 18))
                                .foregroundColor(Color(uiColor: .ppPrimary))

                            Text(Language.get("pos_refund_disposition_notice", alter: "سيتم توجيه المنتج إلى قسم المخزون المخصص وفقًا لحالته المحددة."))
                                .font(AdminType.caption)
                                .foregroundColor(AdminSurface.secondaryText)
                        }
                        .padding(12)
                        .background(Color(uiColor: .ppPrimary).opacity(0.06), in: RoundedRectangle(cornerRadius: 12, style: .continuous))

                        // Reason Selection
                        reasonSection

                        // Summary of Refund
                        refundSummarySection
                    }
                    .padding(AdminSpacing.screenMargin)
                }

                // Submit Button
                VStack(spacing: 8) {
                    Divider().background(AdminSurface.hairline)

                    Button(action: executeRefund) {
                        HStack(spacing: 8) {
                            if viewModel.isSubmittingReversal {
                                ProgressView()
                                    .tint(.white)
                            } else {
                                Image(systemName: "arrow.uturn.backward.circle.fill")
                                    .font(.system(size: 16, weight: .bold))
                            }

                            let amountStr = calculatedRefundAmount.englishDigits(decimals: 2) + " " + Language.get("QAR", alter: "ر.ق")
                            Text(String(format: Language.get("POS_Refund_Confirm_Button", alter: "تأكيد الاسترداد المالي (%@)"), amountStr))
                                .font(AdminType.headline)
                        }
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                        .background(
                            canSubmit ? Color(uiColor: .systemOrange) : Color.gray.opacity(0.4),
                            in: RoundedRectangle(cornerRadius: 16, style: .continuous)
                        )
                    }
                    .buttonStyle(.plain)
                    .disabled(!canSubmit || viewModel.isSubmittingReversal)
                    .padding(.horizontal, AdminSpacing.screenMargin)
                    .padding(.bottom, 16)
                }
                .background(AdminSurface.surface)
            }
        }
        .environment(\.layoutDirection, Language.isRTL() ? .rightToLeft : .leftToRight)
        .onAppear {
            initializeQuantities()
        }
    }

    private func modeButton(title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(AdminType.headline)
                .foregroundColor(isSelected ? .white : AdminSurface.primaryText)
                .frame(maxWidth: .infinity)
                .frame(height: 44)
                .background(
                    isSelected ? Color(uiColor: .ppPrimary) : Color(uiColor: .ppBackgroundSecondary),
                    in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                )
        }
        .buttonStyle(.plain)
    }

    private func initializeQuantities() {
        for item in receipt.items {
            let available = max(0, item.quantity - item.refundedQuantity)
            itemQuantities[item.itemID] = isFullRefund ? available : 0
            if itemConditions[item.itemID] == nil {
                itemConditions[item.itemID] = "sellable"
            }
        }
    }

    private var itemSelectionSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(isFullRefund
                ? Language.get("pos_refund_items_condition_header", alter: "الأصناف المسترجعة وحالة المخزون")
                : Language.get("POS_Refund_Select_Items", alter: "تحديد الأصناف والكميات"))
                .font(AdminType.captionBold)
                .foregroundColor(AdminSurface.secondaryText)

            VStack(spacing: 8) {
                ForEach(receipt.items, id: \.itemID) { item in
                    let available = max(0, item.quantity - item.refundedQuantity)
                    let currentQty = isFullRefund ? available : (itemQuantities[item.itemID] ?? 0)

                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.name)
                                    .font(AdminType.body)
                                    .foregroundColor(AdminSurface.primaryText)

                                Text(verbatim: isFullRefund
                                    ? "\(item.price.englishDigits(decimals: 2)) \(Language.get("QAR", alter: "ر.ق")) • \(Language.get("Quantity", alter: "الكمية")): \(available.englishDigits)"
                                    : "\(item.price.englishDigits(decimals: 2)) \(Language.get("QAR", alter: "ر.ق")) • \(Language.get("Available", alter: "المتاح")): \(available.englishDigits)")
                                    .font(AdminType.caption)
                                    .foregroundColor(AdminSurface.secondaryText)
                            }

                            Spacer()

                            if isFullRefund {
                                Text(verbatim: "\(available.englishDigits)")
                                    .font(AdminType.headline)
                                    .foregroundColor(Color(uiColor: .ppPrimary))
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 4)
                                    .background(Color(uiColor: .ppPrimary).opacity(0.1), in: Capsule())
                            } else {
                                // Stepper: - / qty / +
                                HStack(spacing: 12) {
                                    Button {
                                        if currentQty > 0 {
                                            itemQuantities[item.itemID] = currentQty - 1
                                        }
                                    } label: {
                                        Image(systemName: "minus.circle.fill")
                                            .font(.system(size: 24))
                                            .foregroundColor(currentQty > 0 ? Color(uiColor: .ppPrimary) : Color.gray.opacity(0.3))
                                    }
                                    .buttonStyle(.plain)
                                    .disabled(currentQty <= 0)

                                    Text(verbatim: currentQty.englishDigits)
                                        .font(AdminType.headline)
                                        .frame(minWidth: 24)

                                    Button {
                                        if currentQty < available {
                                            itemQuantities[item.itemID] = currentQty + 1
                                        }
                                    } label: {
                                        Image(systemName: "plus.circle.fill")
                                            .font(.system(size: 24))
                                            .foregroundColor(currentQty < available ? Color(uiColor: .ppPrimary) : Color.gray.opacity(0.3))
                                    }
                                    .buttonStyle(.plain)
                                    .disabled(currentQty >= available)
                                }
                            }
                        }

                        // Condition Selector Chips (Rendered when item has returned quantity)
                        if currentQty > 0 {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(Language.get("pos_refund_condition_title", alter: "حالة المنتج المرتجع ومصير المخزون"))
                                    .font(AdminType.caption)
                                    .foregroundColor(AdminSurface.secondaryText)

                                ScrollView(.horizontal, showsIndicators: false) {
                                    HStack(spacing: 6) {
                                        ForEach(returnConditionOptions) { opt in
                                            let selectedCondition = itemConditions[item.itemID] ?? "sellable"
                                            let isSelected = selectedCondition == opt.id
                                            Button {
                                                itemConditions[item.itemID] = opt.id
                                            } label: {
                                                HStack(spacing: 4) {
                                                    Image(systemName: opt.icon)
                                                        .font(.system(size: 11, weight: .bold))
                                                    Text(Language.get(opt.titleKey, alter: opt.defaultTitle))
                                                        .font(AdminType.caption)
                                                }
                                                .foregroundColor(isSelected ? .white : AdminSurface.primaryText)
                                                .padding(.horizontal, 10)
                                                .padding(.vertical, 6)
                                                .background(
                                                    isSelected ? opt.tint : Color(uiColor: .ppBackgroundSecondary),
                                                    in: Capsule()
                                                )
                                            }
                                            .buttonStyle(.plain)
                                        }
                                    }
                                }
                            }
                            .padding(.top, 2)
                        }
                    }
                    .padding(.vertical, 4)

                    Divider().background(AdminSurface.hairline)
                }
            }
            .padding(14)
            .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
    }

    private var reasonSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(Language.get("POS_Refund_Reason_Title", alter: "سبب الاسترداد (مطلوب)"))
                .font(AdminType.captionBold)
                .foregroundColor(AdminSurface.secondaryText)

            // Preset Chips
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(reasonPresets, id: \.self) { preset in
                        let isSelected = selectedReason == preset
                        Button {
                            selectedReason = preset
                            customReason = preset
                        } label: {
                            Text(preset)
                                .font(AdminType.caption)
                                .foregroundColor(isSelected ? .white : AdminSurface.primaryText)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(
                                    isSelected ? Color(uiColor: .ppPrimary) : Color(uiColor: .ppBackgroundSecondary),
                                    in: Capsule()
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            // Custom Reason Field
            TextField(Language.get("POS_Refund_Reason_Placeholder", alter: "اذكر سبب استرداد العميل..."), text: $customReason)
                .font(AdminType.body)
                .padding(12)
                .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(Color(uiColor: .ppSurfaceBorder), lineWidth: 0.8)
                )
        }
    }

    private var refundSummarySection: some View {
        VStack(spacing: 8) {
            HStack {
                Text("المبلغ المسترد الإجمالي")
                    .font(AdminType.headline)
                    .foregroundColor(AdminSurface.primaryText)

                Spacer()

                Text(verbatim: calculatedRefundAmount.englishDigits(decimals: 2) + " " + Language.get("QAR", alter: "ر.ق"))
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundColor(Color(uiColor: .systemOrange))
                    .monospacedDigit()
            }
        }
        .padding(14)
        .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var calculatedRefundAmount: Double {
        if isFullRefund {
            return max(0.0, receipt.total - receipt.refundedAmount)
        } else {
            var sum: Double = 0
            for item in receipt.items {
                let qty = itemQuantities[item.itemID] ?? 0
                sum += Double(qty) * item.price
            }
            return min(sum, max(0.0, receipt.total - receipt.refundedAmount))
        }
    }

    private var canSubmit: Bool {
        let amount = calculatedRefundAmount
        let reason = customReason.trimmingCharacters(in: .whitespacesAndNewlines)
        return amount > 0 && reason.count >= 3
    }

    private func executeRefund() {
        let finalReason = customReason.trimmingCharacters(in: .whitespacesAndNewlines)
        let amount = calculatedRefundAmount

        var mapped: [[String: Any]] = []
        for item in receipt.items {
            let available = max(0, item.quantity - item.refundedQuantity)
            let qty = isFullRefund ? available : (itemQuantities[item.itemID] ?? 0)
            if qty > 0 {
                let cond = itemConditions[item.itemID] ?? "sellable"
                let disp = returnConditionOptions.first(where: { $0.id == cond })?.defaultDisposition ?? "return_to_stock"
                let reasonCode = cond == "sellable" ? "customer_return_sellable" : "customer_return_\(cond)"
                mapped.append([
                    "productId": item.itemID,
                    "quantity": qty,
                    "refundAmount": Double(qty) * item.price,
                    "condition": cond,
                    "disposition": disp,
                    "reasonCode": reasonCode,
                    "notes": finalReason
                ])
            }
        }
        let itemsPayload: [[String: Any]]? = mapped.isEmpty ? nil : mapped

        Task {
            let success = await viewModel.refundTransaction(
                receipt: receipt,
                refundAmount: amount,
                refundItems: itemsPayload,
                reason: finalReason
            )
            if success {
                // Update local receipt instance with refund facts
                receipt.refundedAmount += amount
                receipt.refundReason = finalReason
                receipt.refundedAt = Date()
                let cashier = receipt.cashierName ?? receipt.operatorID
                if !cashier.isEmpty {
                    receipt.refundedBy = cashier
                }
                if receipt.refundedAmount >= (receipt.total - 0.001) {
                    receipt.status = "refunded"
                } else {
                    receipt.status = "partially_refunded"
                }
                for item in receipt.items {
                    let available = max(0, item.quantity - item.refundedQuantity)
                    let qty = isFullRefund ? available : (itemQuantities[item.itemID] ?? 0)
                    if qty > 0 {
                        item.refundedQuantity += qty
                    }
                }
                dismiss()
                onSuccess(receipt)
            }
        }
    }
}

// MARK: - POS Cancel / Void Confirmation Sheet (POSTransactionVoidStudio)

private struct VoidReasonPresetItem: Identifiable {
    let id: String
    let icon: String
    let title: String
}

struct TactileSlideToVoidControl: View {
    let isEnabled: Bool
    let isSubmitting: Bool
    let onConfirm: () -> Void

    @State private var dragOffset: CGFloat = 0
    @State private var isArmed: Bool = false
    @Environment(\.layoutDirection) private var layoutDirection

    private let thumbSize: CGFloat = 46
    private let trackHeight: CGFloat = 56

    var body: some View {
        GeometryReader { proxy in
            let totalWidth = proxy.size.width
            let maxSlide = max(10, totalWidth - thumbSize - 8)
            let isRTL = layoutDirection == .rightToLeft
            let progress = max(0, min(1, abs(dragOffset) / maxSlide))

            ZStack(alignment: isRTL ? .trailing : .leading) {
                // Background Track
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color(uiColor: .ppElevatedSurface))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .strokeBorder(
                                isEnabled
                                    ? Color(uiColor: .systemRed).opacity(0.3 + 0.4 * Double(progress))
                                    : Color(uiColor: .ppSurfaceBorder),
                                lineWidth: 1.2
                            )
                    )

                // Fill progress
                if isEnabled && progress > 0 {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color(uiColor: .systemRed).opacity(0.35),
                                    Color(uiColor: .systemRed).opacity(0.85)
                                ],
                                startPoint: isRTL ? .trailing : .leading,
                                endPoint: isRTL ? .leading : .trailing
                            )
                        )
                        .frame(width: max(thumbSize + 8, (progress * maxSlide) + thumbSize + 4))
                }

                // Centered Prompt or In-Flight Indicator
                HStack(spacing: 8) {
                    if isSubmitting {
                        ProgressView()
                            .tint(.white)
                        Text(Language.get("POS_Void_Submitting", alter: "جاري إبطال المعاملة واسترداد المخزون..."))
                            .font(AdminType.captionBold)
                            .foregroundColor(.white)
                    } else if !isEnabled {
                        Image(systemName: "lock.fill")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(AdminSurface.secondaryText)
                        Text(Language.get("POS_Cancel_Reason_Placeholder", alter: "اكتب سبب إبطال هذه المعاملة للتفعيل..."))
                            .font(AdminType.caption)
                            .foregroundColor(AdminSurface.secondaryText)
                    } else {
                        Image(systemName: isRTL ? "chevron.left.2" : "chevron.right.2")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(progress > 0.4 ? .white : Color(uiColor: .systemRed))
                        Text(Language.get("POS_Void_Slide_To_Confirm", alter: "اسحب لإبطال المعاملة واسترداد المخزون"))
                            .font(AdminType.headline)
                            .foregroundColor(progress > 0.4 ? .white : AdminSurface.primaryText)
                    }
                }
                .frame(maxWidth: .infinity)
                .opacity(isSubmitting ? 1.0 : (1.0 - Double(progress * 0.7)))

                // Draggable Thumb Knob
                if !isSubmitting {
                    HStack {
                        ZStack {
                            Circle()
                                .fill(
                                    isEnabled
                                        ? Color(uiColor: .systemRed)
                                        : Color.gray.opacity(0.35)
                                )
                                .shadow(
                                    color: isEnabled ? Color(uiColor: .systemRed).opacity(0.35) : .clear,
                                    radius: 6,
                                    y: 2
                                )

                            Image(systemName: isEnabled ? "xmark.octagon.fill" : "lock.fill")
                                .font(.system(size: 18, weight: .bold))
                                .foregroundColor(.white)
                        }
                        .frame(width: thumbSize, height: thumbSize)
                        .offset(x: isRTL ? -dragOffset : dragOffset)
                        .gesture(
                            DragGesture(minimumDistance: 0)
                                .onChanged { value in
                                    guard isEnabled else { return }
                                    let raw = isRTL ? -value.translation.width : value.translation.width
                                    let clamped = max(0, min(maxSlide, raw))
                                    dragOffset = clamped

                                    if clamped >= maxSlide * 0.82 && !isArmed {
                                        isArmed = true
                                        UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
                                    } else if clamped < maxSlide * 0.82 && isArmed {
                                        isArmed = false
                                    }
                                }
                                .onEnded { value in
                                    guard isEnabled else { return }
                                    let raw = isRTL ? -value.translation.width : value.translation.width
                                    if raw >= maxSlide * 0.82 {
                                        dragOffset = maxSlide
                                        UINotificationFeedbackGenerator().notificationOccurred(.success)
                                        onConfirm()
                                    } else {
                                        withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
                                            dragOffset = 0
                                            isArmed = false
                                        }
                                    }
                                }
                        )
                    }
                    .padding(.horizontal, 4)
                }
            }
            .frame(height: trackHeight)
        }
        .frame(height: trackHeight)
    }
}

struct POSCancelConfirmationSheet: View {
    let receipt: PPPOSReceipt
    @ObservedObject var viewModel: POSHistoryViewModel
    let onSuccess: () -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var cancelReason: String = ""
    @State private var selectedPresetId: String? = nil

    private let presets: [VoidReasonPresetItem] = [
        VoidReasonPresetItem(
            id: "item_error",
            icon: "cart.badge.minus",
            title: Language.get("POS_Void_Reason_Preset_1", alter: "خطأ في إدخال الأصناف أو السعر")
        ),
        VoidReasonPresetItem(
            id: "duplicate",
            icon: "doc.on.doc.fill",
            title: Language.get("POS_Void_Reason_Preset_2", alter: "عملية مكررة بالخطأ")
        ),
        VoidReasonPresetItem(
            id: "payment_failed",
            icon: "creditcard.trianglebadge.exclamationmark",
            title: Language.get("POS_Void_Reason_Preset_3", alter: "فشل استلام الدفع الخارجي")
        ),
        VoidReasonPresetItem(
            id: "customer_void",
            icon: "person.crop.circle.badge.xmark",
            title: Language.get("POS_Void_Reason_Preset_4", alter: "طلب العميل الإلغاء فوراً")
        )
    ]

    var body: some View {
        ZStack {
            AdminSurface.background.ignoresSafeArea()

            VStack(spacing: 0) {
                // Header Bar
                studioHeader

                // Scrollable Content
                ScrollView(showsIndicators: false) {
                    VStack(spacing: AdminSpacing.base) {
                        // Dossier Identity Card
                        dossierIdentityCard

                        // Financial Reversal Hero Display
                        financialReversalHero

                        // Live Restock Manifest
                        restockManifestSection

                        // System Impact Matrix (4 Pillars)
                        systemImpactMatrix

                        // Error Banner if present
                        if let error = viewModel.reversalError {
                            AdminErrorBanner(message: error)
                        }

                        // Intelligent Reason Studio
                        reasonStudioSection

                        Spacer(minLength: 20)
                    }
                    .padding(.horizontal, AdminSpacing.screenMargin)
                    .padding(.top, AdminSpacing.sm)
                    .padding(.bottom, 90)
                }

                // Pinned Bottom Slide-to-Void Dock
                bottomDock
            }
        }
        .environment(\.layoutDirection, Language.isRTL() ? .rightToLeft : .leftToRight)
    }

    // MARK: - Header Bar

    private var studioHeader: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Image(systemName: "shield.lefthalf.filled")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(Color(uiColor: .systemRed))
                    Text(Language.get("POS_Void_Studio_Title", alter: "وحدة إبطال المعاملة واسترداد المخزون"))
                        .font(AdminType.headline)
                        .foregroundColor(AdminSurface.primaryText)
                }

                Text(Language.get("POS_Void_Dossier_Badge", alter: "قيد تدقيق مالي وإداري قطعي"))
                    .font(AdminType.caption2)
                    .foregroundColor(AdminSurface.secondaryText)
            }

            Spacer()

            AdminSquircleCloseButton {
                dismiss()
            }
        }
        .padding(.horizontal, AdminSpacing.screenMargin)
        .padding(.vertical, AdminSpacing.md)
        .background(AdminSurface.surface.opacity(0.85))
        .overlay(
            Divider().background(AdminSurface.hairline),
            alignment: .bottom
        )
    }

    // MARK: - Dossier Identity Card

    private var dossierIdentityCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text(verbatim: POSReceiptFormat.receiptID(receipt.receiptID))
                    .font(.system(size: 14, weight: .bold, design: .monospaced))
                    .foregroundColor(Color(uiColor: .ppPrimary))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Color(uiColor: .ppPrimary).opacity(0.12), in: RoundedRectangle(cornerRadius: 8, style: .continuous))

                if let branch = receipt.branchName ?? BranchContextStore.shared.activeBranch?.localizedName() {
                    HStack(spacing: 4) {
                        Image(systemName: "mappin.circle.fill")
                            .font(.system(size: 12))
                        Text(branch)
                            .font(AdminType.caption)
                    }
                    .foregroundColor(AdminSurface.secondaryText)
                }

                Spacer()

                HStack(spacing: 4) {
                    Image(systemName: paymentMethodIcon)
                        .font(.system(size: 12))
                    Text(paymentMethodLabel)
                        .font(AdminType.captionBold)
                }
                .foregroundColor(AdminSurface.primaryText)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color(uiColor: .ppBackgroundSecondary), in: Capsule())
            }

            HStack(spacing: 12) {
                if let cashier = receipt.cashierName ?? (!receipt.operatorID.isEmpty ? receipt.operatorID : nil) {
                    HStack(spacing: 4) {
                        Image(systemName: "person.badge.shield.checkmark.fill")
                            .font(.system(size: 11))
                            .foregroundColor(AdminSurface.secondaryText)
                        Text(verbatim: cashier)
                            .font(AdminType.caption2)
                            .foregroundColor(AdminSurface.secondaryText)
                    }
                }

                if let createdAt = receipt.createdAt {
                    HStack(spacing: 4) {
                        Image(systemName: "clock.fill")
                            .font(.system(size: 11))
                            .foregroundColor(AdminSurface.secondaryText)
                        Text(POSReceiptFormat.relativeDate(createdAt))
                            .font(AdminType.caption2)
                            .foregroundColor(AdminSurface.secondaryText)
                    }
                }

                if !receipt.customerName.isEmpty {
                    HStack(spacing: 4) {
                        Image(systemName: "person.fill")
                            .font(.system(size: 11))
                            .foregroundColor(Color(uiColor: .ppPrimary))
                        Text(receipt.customerName)
                            .font(AdminType.caption2Bold)
                            .foregroundColor(AdminSurface.primaryText)
                    }
                }
            }
        }
        .padding(14)
        .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(AdminSurface.hairline, lineWidth: 0.8)
        )
    }

    // MARK: - Financial Reversal Hero Display

    private var financialReversalHero: some View {
        VStack(spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(Language.get("POS_Void_Reversal_Hero", alter: "المبلغ المطلوب إرجاعه للعميل"))
                        .font(AdminType.captionBold)
                        .foregroundColor(Color(uiColor: .systemRed))

                    Text(verbatim: "−" + receipt.total.englishDigits(decimals: 2) + " " + Language.get("QAR", alter: "ر.ق"))
                        .font(.system(size: 30, weight: .black, design: .rounded))
                        .foregroundColor(Color(uiColor: .systemRed))
                        .monospacedDigit()
                }

                Spacer()

                ZStack {
                    Circle()
                        .fill(Color(uiColor: .systemRed).opacity(0.12))
                        .frame(width: 54, height: 54)
                    Image(systemName: "arrow.counterclockwise.circle.fill")
                        .font(.system(size: 32, weight: .bold))
                        .foregroundColor(Color(uiColor: .systemRed))
                }
            }

            Divider().background(Color(uiColor: .systemRed).opacity(0.2))

            HStack(spacing: 6) {
                Image(systemName: "info.circle.fill")
                    .font(.system(size: 12))
                    .foregroundColor(Color(uiColor: .systemRed))
                Text(paymentSettlementHint)
                    .font(AdminType.caption2)
                    .foregroundColor(AdminSurface.secondaryText)
                Spacer()
            }
        }
        .padding(16)
        .background(Color(uiColor: .systemRed).opacity(0.06), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Color(uiColor: .systemRed).opacity(0.25), lineWidth: 1)
        )
    }

    // MARK: - Live Restock Manifest

    private var restockManifestSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "shippingbox.fill")
                        .font(.system(size: 14))
                        .foregroundColor(Color(uiColor: .systemGreen))
                    Text(Language.get("POS_Void_Restock_Manifest", alter: "بيان إعادة الأصناف لمخزون الفرع"))
                        .font(AdminType.captionBold)
                        .foregroundColor(AdminSurface.primaryText)
                }

                Spacer()

                let itemsCount = receipt.items.count.englishDigits
                Text(String(format: Language.get("POS_Items_Count", alter: "%@ أصناف"), itemsCount))
                    .font(AdminType.caption2)
                    .foregroundColor(AdminSurface.secondaryText)
            }

            VStack(spacing: 8) {
                ForEach(receipt.items, id: \.itemID) { item in
                    HStack(spacing: 12) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(Color(uiColor: .systemGreen).opacity(0.12))
                                .frame(width: 38, height: 38)
                            Image(systemName: "arrow.down.left.circle.fill")
                                .font(.system(size: 20))
                                .foregroundColor(Color(uiColor: .systemGreen))
                        }

                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.name)
                                .font(AdminType.bodyBold)
                                .foregroundColor(AdminSurface.primaryText)
                                .lineLimit(1)

                            HStack(spacing: 6) {
                                if let tag = item.unitRingTags.first, !tag.isEmpty {
                                    Text(verbatim: "#" + tag)
                                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                                        .foregroundColor(Color(uiColor: .ppPrimary))
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(Color(uiColor: .ppPrimary).opacity(0.1), in: Capsule())
                                }

                                Text(verbatim: item.price.englishDigits(decimals: 2) + " " + Language.get("QAR", alter: "ر.ق"))
                                    .font(AdminType.caption2)
                                    .foregroundColor(AdminSurface.secondaryText)
                            }
                        }

                        Spacer()

                        VStack(alignment: .trailing, spacing: 2) {
                            Text(String(format: Language.get("POS_Void_Restock_Unit", alter: "+%@ للمخزون"), item.quantity.englishDigits))
                                .font(.system(size: 12, weight: .bold))
                                .foregroundColor(Color(uiColor: .systemGreen))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(Color(uiColor: .systemGreen).opacity(0.12), in: Capsule())

                            Text(verbatim: item.lineTotal.englishDigits(decimals: 2) + " " + Language.get("QAR", alter: "ر.ق"))
                                .font(AdminType.captionBold)
                                .foregroundColor(AdminSurface.primaryText)
                        }
                    }
                    .padding(10)
                    .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
            }
        }
        .padding(14)
        .background(Color(uiColor: .ppBackgroundSecondary), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    // MARK: - System Impact Matrix

    private var systemImpactMatrix: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(Language.get("POS_Void_Impact_Title", alter: "أثر العملية على النظام فور التأكيد"))
                .font(AdminType.captionBold)
                .foregroundColor(AdminSurface.secondaryText)

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                impactPill(
                    icon: "shippingbox.and.arrow.backward.fill",
                    color: Color(uiColor: .systemGreen),
                    title: Language.get("POS_Void_Impact_Inventory_Title", alter: "المخزون"),
                    desc: Language.get("POS_Void_Impact_Inventory_Desc", alter: "إعادة الأصناف فوراً لرفوف الفرع")
                )

                impactPill(
                    icon: "banknote.fill",
                    color: Color(uiColor: .systemOrange),
                    title: Language.get("POS_Void_Impact_Finance_Title", alter: "المالية والخزينة"),
                    desc: Language.get("POS_Void_Impact_Finance_Desc", alter: "خصم القيمة من مبيعات الوردية اليومية")
                )

                impactPill(
                    icon: "shield.lefthalf.filled",
                    color: Color(uiColor: .ppPrimary),
                    title: Language.get("POS_Void_Impact_Audit_Title", alter: "سجل التدقيق"),
                    desc: Language.get("POS_Void_Impact_Audit_Desc", alter: "توثيق العملية باسم المشغل والتوقيت")
                )

                impactPill(
                    icon: "lock.shield.fill",
                    color: Color(uiColor: .systemRed),
                    title: Language.get("POS_Void_Impact_Finality_Title", alter: "إجراء قطعي"),
                    desc: Language.get("POS_Void_Impact_Finality_Desc", alter: "لا يمكن التراجع عن الإبطال نهائياً")
                )
            }
        }
    }

    private func impactPill(icon: String, color: Color, title: String, desc: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(color)
                Text(title)
                    .font(AdminType.captionBold)
                    .foregroundColor(AdminSurface.primaryText)
            }

            Text(desc)
                .font(AdminType.caption2)
                .foregroundColor(AdminSurface.secondaryText)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(AdminSurface.hairline, lineWidth: 0.8)
        )
    }

    // MARK: - Intelligent Reason Studio

    private var reasonStudioSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(Language.get("POS_Void_Reason_Section", alter: "سبب الإبطال والإلغاء (مطلوب)"))
                    .font(AdminType.captionBold)
                    .foregroundColor(AdminSurface.primaryText)

                Spacer()

                let count = cancelReason.trimmingCharacters(in: .whitespacesAndNewlines).count
                HStack(spacing: 4) {
                    if count >= 3 {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 11))
                            .foregroundColor(Color(uiColor: .systemGreen))
                    }
                    Text(verbatim: "\(count.englishDigits) / 500")
                        .font(AdminType.caption2)
                        .foregroundColor(count >= 3 ? Color(uiColor: .systemGreen) : AdminSurface.secondaryText)
                }
            }

            // 2x2 Preset Tiles
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                ForEach(presets) { preset in
                    let isSelected = selectedPresetId == preset.id
                    Button {
                        selectedPresetId = preset.id
                        cancelReason = preset.title
                        UISelectionFeedbackGenerator().selectionChanged()
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: preset.icon)
                                .font(.system(size: 14))
                                .foregroundColor(isSelected ? .white : Color(uiColor: .systemRed))

                            Text(preset.title)
                                .font(AdminType.caption)
                                .foregroundColor(isSelected ? .white : AdminSurface.primaryText)
                                .lineLimit(2)
                                .multilineTextAlignment(.leading)

                            Spacer(minLength: 0)
                        }
                        .padding(10)
                        .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
                        .background(
                            isSelected ? Color(uiColor: .systemRed) : AdminSurface.surface,
                            in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .strokeBorder(
                                    isSelected ? Color(uiColor: .systemRed) : AdminSurface.hairline,
                                    lineWidth: isSelected ? 1.5 : 0.8
                                )
                        )
                    }
                    .buttonStyle(.plain)
                }
            }

            // Freeform Reason Input
            TextField(Language.get("POS_Void_Notes_Prompt", alter: "ملاحظات إضافية وتفاصيل السبب..."), text: $cancelReason)
                .font(AdminType.body)
                .padding(12)
                .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(
                            canSubmit ? Color(uiColor: .systemRed).opacity(0.5) : AdminSurface.hairline,
                            lineWidth: 0.8
                        )
                )
        }
        .padding(14)
        .background(Color(uiColor: .ppBackgroundSecondary), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    // MARK: - Pinned Bottom Dock

    private var bottomDock: some View {
        VStack(spacing: 8) {
            TactileSlideToVoidControl(
                isEnabled: canSubmit,
                isSubmitting: viewModel.isSubmittingReversal,
                onConfirm: executeCancel
            )
        }
        .padding(.horizontal, AdminSpacing.screenMargin)
        .padding(.top, 10)
        .padding(.bottom, 16)
        .background(
            AdminSurface.surface
                .shadow(color: Color.black.opacity(0.08), radius: 10, y: -4)
                .ignoresSafeArea(edges: .bottom)
        )
    }

    // MARK: - Helpers

    private var canSubmit: Bool {
        cancelReason.trimmingCharacters(in: .whitespacesAndNewlines).count >= 3
    }

    private var paymentMethodIcon: String {
        switch receipt.paymentMethod.lowercased() {
        case "cash": return "banknote.fill"
        case "card": return "creditcard.fill"
        case "qib": return "qrcode"
        default: return "creditcard.and.123"
        }
    }

    private var paymentMethodLabel: String {
        switch receipt.paymentMethod.lowercased() {
        case "cash": return Language.get("POS_Payment_Cash", alter: "نقداً")
        case "card": return Language.get("POS_Payment_Card", alter: "بطاقة")
        case "qib": return "QIB Pay"
        default: return receipt.paymentMethod
        }
    }

    private var paymentSettlementHint: String {
        if receipt.paymentMethod.lowercased() == "cash" {
            return Language.get("POS_Void_Hint_Cash", alter: "تم الدفع نقداً: يلزم إعادة المبلغ للعميل من درج النقدية بالفرع.")
        } else {
            return Language.get("POS_Void_Hint_Card", alter: "تم الدفع إلكترونياً: يلزم إرجاع المبلغ عبر جهاز نقاط البيع البنكي.")
        }
    }

    private func executeCancel() {
        let reason = cancelReason.trimmingCharacters(in: .whitespacesAndNewlines)
        Task {
            let success = await viewModel.cancelTransaction(receipt: receipt, reason: reason)
            if success {
                dismiss()
                onSuccess()
            }
        }
    }
}
