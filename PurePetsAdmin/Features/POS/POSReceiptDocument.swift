//
//  POSReceiptDocument.swift
//  PurePetsAdmin
//
//  Native, localized post-sale receipt preview, PDF export, share, and AirPrint.
//  The authoritative projection is read from transactions/{transactionId}.
//

import SwiftUI
import UIKit

// MARK: - Receipt Projection

struct POSCompletedReceipt: Identifiable, Sendable {
    struct Line: Identifiable, Sendable {
        let id: String
        let name: String
        let quantity: Int
        let unitPrice: Double
        let lineTotal: Double
        let ringTags: [String]
    }

    let transactionID: String
    let createdAt: Date
    let lines: [Line]
    let subtotal: Double
    let discount: Double
    let total: Double
    let cashReceived: Double
    let changeDue: Double
    let paymentMethod: String
    let currency: String
    let status: String
    let customerName: String
    let customerPhone: String
    let note: String
    let isAuthoritative: Bool

    var id: String { transactionID }

    init(receipt: PPPOSReceipt) {
        transactionID = receipt.receiptID
        createdAt = receipt.createdAt ?? Date()
        lines = receipt.items.enumerated().map { index, item in
            let quantity = max(item.quantity, 1)
            let derivedTotal = item.price * Double(quantity)
            return Line(
                id: item.itemID.isEmpty ? "line-\(index)" : "\(item.itemID)-\(index)",
                name: item.name.isEmpty
                    ? Language.get("POS_Receipt_UnnamedItem", alter: "عنصر")
                    : item.name,
                quantity: quantity,
                unitPrice: item.price,
                lineTotal: item.lineTotal > 0 ? item.lineTotal : derivedTotal,
                ringTags: item.unitRingTags
            )
        }
        subtotal = receipt.subtotal > 0 ? receipt.subtotal : receipt.total + receipt.discount
        discount = max(receipt.discount, 0)
        total = receipt.total
        cashReceived = max(receipt.cashReceived, 0)
        changeDue = max(receipt.changeDue, 0)
        paymentMethod = receipt.paymentMethod
        currency = receipt.currency.isEmpty ? "QAR" : receipt.currency
        status = receipt.status.isEmpty ? "completed" : receipt.status
        customerName = receipt.customerName
        customerPhone = receipt.customerPhone
        note = receipt.note
        isAuthoritative = true
    }

    /// Confirmed-response fallback used only when the post-commit Firestore read
    /// is temporarily unavailable. It preserves the server transaction ID/total
    /// and the exact cart snapshot that produced the accepted command.
    init(
        transactionID: String,
        total: Double,
        currency: String,
        paymentMethod: String,
        cashReceived: Double,
        cartItems: [POSCartItem]
    ) {
        self.transactionID = transactionID
        createdAt = Date()
        lines = cartItems.enumerated().map { index, item in
            Line(
                id: "\(item.accessory.accessoryID)-\(index)",
                name: item.accessory.name,
                quantity: item.quantity,
                unitPrice: item.unitPriceDisplay,
                lineTotal: item.lineTotal,
                ringTags: item.unitRingTags
            )
        }
        subtotal = total
        discount = 0
        self.total = total
        self.cashReceived = paymentMethod == "cash" ? max(cashReceived, total) : 0
        changeDue = paymentMethod == "cash" ? max(cashReceived - total, 0) : 0
        self.paymentMethod = paymentMethod
        self.currency = currency.isEmpty ? "QAR" : currency
        status = "completed"
        customerName = ""
        customerPhone = ""
        note = ""
        isAuthoritative = false
    }
}

// MARK: - Receipt Sheet

struct POSCompletedReceiptSheet: View {
    let receipt: POSCompletedReceipt
    let notice: String?

    @Environment(\.dismiss) private var dismiss
    @State private var temporaryReceiptURL: URL?
    @State private var isSharing = false
    @State private var feedbackMessage: String?

    var body: some View {
        ZStack {
            AdminSurface.background.ignoresSafeArea()

            VStack(spacing: 0) {
                header

                ScrollView {
                    VStack(spacing: 14) {
                        if let notice, !notice.isEmpty {
                            noticeBanner(notice)
                        }
                        receiptPaper
                    }
                    .padding(.horizontal, 18)
                    .padding(.top, 8)
                    .padding(.bottom, 20)
                }

                actionBar
            }
        }
        .environment(\.layoutDirection, Language.isRTL() ? .rightToLeft : .leftToRight)
        .sheet(isPresented: $isSharing, onDismiss: removeTemporaryReceipt) {
            if let temporaryReceiptURL {
                POSReceiptShareSheet(url: temporaryReceiptURL)
            }
        }
        .alert(
            Language.get("POS_Receipt_ActionFailedTitle", alter: "تعذر تجهيز الإيصال"),
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

    private var header: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color.green.opacity(0.13))
                    .frame(width: 44, height: 44)
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundColor(.green)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(Language.get("POS_Receipt_Ready", alter: "الإيصال جاهز"))
                    .font(Font.custom("Beiruti-Bold", size: 21, relativeTo: .headline))
                    .foregroundColor(AdminSurface.primaryText)
                Text(Language.get("POS_Receipt_Ready_Subtitle", alter: "يمكنك طباعة إيصال عملية البيع المكتملة أو مشاركته."))
                    .font(Font.custom("Beiruti-Regular", size: 13, relativeTo: .caption))
                    .foregroundColor(AdminSurface.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 8)

            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(AdminSurface.primaryText)
                    .frame(width: 40, height: 40)
                    .background(AdminSurface.control, in: Circle())
            }
            .accessibilityLabel(Language.get("Close", alter: "إغلاق"))
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .background(AdminSurface.surface)
        .overlay(alignment: .bottom) {
            Rectangle().fill(AdminSurface.hairline).frame(height: 1)
        }
    }

    private func noticeBanner(_ message: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.orange)
                .padding(.top, 1)
            Text(message)
                .font(Font.custom("Beiruti-Regular", size: 13, relativeTo: .caption))
                .foregroundColor(AdminSurface.primaryText)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(Color.orange.opacity(0.10), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.orange.opacity(0.24), lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
    }

    private var receiptPaper: some View {
        VStack(spacing: 16) {
            VStack(spacing: 7) {
                Image("LogoV5")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 68, height: 68)
                    .accessibilityHidden(true)

                Text(Language.isRTL() ? "بيور بتس" : "PURE PETS")
                    .font(Font.custom("Beiruti-Bold", size: 22, relativeTo: .title3))
                    .foregroundColor(AdminSurface.primaryText)

                Text(Language.get("POS_Receipt_Title", alter: "إيصال بيع"))
                    .font(Font.custom("Beiruti-Medium", size: 15, relativeTo: .callout))
                    .foregroundColor(AdminSurface.secondaryText)
            }

            receiptMetadata
            Divider().background(AdminSurface.hairline)
            receiptLines
            Divider().background(AdminSurface.hairline)
            totals

            if !receipt.customerName.isEmpty || !receipt.customerPhone.isEmpty || !receipt.note.isEmpty {
                Divider().background(AdminSurface.hairline)
                customerDetails
            }

            VStack(spacing: 6) {
                Text(Language.get("POS_Receipt_ThankYou", alter: "شكرًا لاختياركم بيوربيتس"))
                    .font(Font.custom("Beiruti-Bold", size: 14, relativeTo: .caption))
                    .foregroundColor(AdminSurface.primary)
                    .multilineTextAlignment(.center)

                VStack(spacing: 3) {
                    HStack(spacing: 5) {
                        Image(systemName: "globe")
                            .font(.system(size: 10))
                        Text("https://pure-pets.net")
                            .font(Font.custom("Beiruti-Regular", size: 11, relativeTo: .caption2))
                    }
                    .foregroundColor(AdminSurface.secondaryText)

                    HStack(spacing: 10) {
                        HStack(spacing: 4) {
                            Image(systemName: "envelope.fill")
                                .font(.system(size: 9))
                            Text("support@pure-pets.net")
                                .font(Font.custom("Beiruti-Regular", size: 11, relativeTo: .caption2))
                        }

                        Text("•")
                            .foregroundColor(AdminSurface.hairline)

                        HStack(spacing: 4) {
                            Image(systemName: "phone.fill")
                                .font(.system(size: 9))
                            Text("+974 5999 7720")
                                .font(Font.custom("Beiruti-Bold", size: 11, relativeTo: .caption2))
                                .monospacedDigit()
                        }
                    }
                    .foregroundColor(AdminSurface.secondaryText)
                }
                .padding(.top, 2)
            }
            .padding(.top, 2)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 22)
        .frame(maxWidth: 520)
        .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(AdminSurface.hairline, lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.07), radius: 18, y: 8)
        .accessibilityElement(children: .contain)
    }

    private var receiptMetadata: some View {
        VStack(spacing: 8) {
            receiptValueRow(
                Language.get("POS_Receipt_Transaction", alter: "رقم المعاملة"),
                value: receipt.transactionID,
                monospaced: true
            )
            receiptValueRow(
                Language.get("POS_Receipt_Date", alter: "التاريخ"),
                value: POSReceiptFormat.date(receipt.createdAt)
            )
            receiptValueRow(
                Language.get("POS_Receipt_Payment", alter: "طريقة الدفع"),
                value: POSReceiptFormat.paymentMethod(receipt.paymentMethod)
            )
            receiptValueRow(
                Language.get("POS_Receipt_Status", alter: "الحالة"),
                value: Language.get("POS_Receipt_Completed", alter: "مكتملة")
            )
        }
    }

    private var receiptLines: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(Language.get("POS_Receipt_Items", alter: "العناصر"))
                .font(Font.custom("Beiruti-Bold", size: 14, relativeTo: .caption))
                .foregroundColor(AdminSurface.secondaryText)

            ForEach(receipt.lines) { line in
                HStack(alignment: .top, spacing: 10) {
                    Text("\(line.quantity)×")
                        .font(Font.custom("Beiruti-Bold", size: 14, relativeTo: .caption))
                        .foregroundColor(AdminSurface.primary)
                        .monospacedDigit()
                        .frame(minWidth: 28, alignment: .leading)

                    VStack(alignment: .leading, spacing: 3) {
                        Text(line.name)
                            .font(Font.custom("Beiruti-Bold", size: 15, relativeTo: .callout))
                            .foregroundColor(AdminSurface.primaryText)
                            .fixedSize(horizontal: false, vertical: true)

                        if !line.ringTags.isEmpty {
                            Text(
                                Language.get("POS_Receipt_Rings", alter: "الحلقات / الوسوم")
                                + ": " + line.ringTags.joined(separator: "، ")
                            )
                            .font(Font.custom("Beiruti-Regular", size: 12, relativeTo: .caption2))
                            .foregroundColor(AdminSurface.secondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                        }
                    }

                    Spacer(minLength: 8)

                    Text(POSReceiptFormat.currency(line.lineTotal, code: receipt.currency))
                        .font(Font.custom("Beiruti-Bold", size: 15, relativeTo: .callout))
                        .foregroundColor(AdminSurface.primaryText)
                        .monospacedDigit()
                        .multilineTextAlignment(.trailing)
                }
                .accessibilityElement(children: .combine)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var totals: some View {
        VStack(spacing: 9) {
            receiptValueRow(
                Language.get("POS_Receipt_Subtotal", alter: "المجموع الفرعي"),
                value: POSReceiptFormat.currency(receipt.subtotal, code: receipt.currency)
            )
            if receipt.discount > 0 {
                receiptValueRow(
                    Language.get("POS_Receipt_Discount", alter: "الخصم"),
                    value: "−" + POSReceiptFormat.currency(receipt.discount, code: receipt.currency)
                )
            }

            HStack(alignment: .firstTextBaseline) {
                Text(Language.get("POS_Receipt_Total", alter: "الإجمالي"))
                    .font(Font.custom("Beiruti-Bold", size: 20, relativeTo: .headline))
                    .foregroundColor(AdminSurface.primaryText)
                Spacer()
                Text(POSReceiptFormat.currency(receipt.total, code: receipt.currency))
                    .font(Font.custom("Beiruti-Bold", size: 26, relativeTo: .title2))
                    .foregroundColor(AdminSurface.primary)
                    .monospacedDigit()
            }

            if receipt.paymentMethod.lowercased() == "cash" {
                receiptValueRow(
                    Language.get("POS_Receipt_CashReceived", alter: "المبلغ المستلم"),
                    value: POSReceiptFormat.currency(receipt.cashReceived, code: receipt.currency)
                )
                receiptValueRow(
                    Language.get("POS_Receipt_ChangeDue", alter: "الباقي"),
                    value: POSReceiptFormat.currency(receipt.changeDue, code: receipt.currency)
                )
            }
        }
    }

    private var customerDetails: some View {
        VStack(spacing: 8) {
            if !receipt.customerName.isEmpty {
                receiptValueRow(
                    Language.get("POS_Receipt_Customer", alter: "العميل"),
                    value: receipt.customerName
                )
            }
            if !receipt.customerPhone.isEmpty {
                receiptValueRow(
                    Language.get("POS_Receipt_Phone", alter: "الهاتف"),
                    value: receipt.customerPhone,
                    monospaced: true
                )
            }
            if !receipt.note.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text(Language.get("POS_Receipt_Notes", alter: "ملاحظات"))
                        .font(Font.custom("Beiruti-Regular", size: 12, relativeTo: .caption2))
                        .foregroundColor(AdminSurface.secondaryText)
                    Text(receipt.note)
                        .font(Font.custom("Beiruti-Regular", size: 13, relativeTo: .caption))
                        .foregroundColor(AdminSurface.primaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func receiptValueRow(_ label: String, value: String, monospaced: Bool = false) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(label)
                .font(Font.custom("Beiruti-Regular", size: 13, relativeTo: .caption))
                .foregroundColor(AdminSurface.secondaryText)
            Spacer(minLength: 12)
            Group {
                if monospaced {
                    Text(value).monospacedDigit()
                } else {
                    Text(value)
                }
            }
            .font(Font.custom("Beiruti-Bold", size: 13, relativeTo: .caption))
            .foregroundColor(AdminSurface.primaryText)
            .multilineTextAlignment(.trailing)
            .lineLimit(3)
            .minimumScaleFactor(0.72)
        }
        .accessibilityElement(children: .combine)
    }

    private var actionBar: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                receiptActionButton(
                    title: Language.get("POS_Receipt_Print", alter: "طباعة"),
                    symbol: "printer.fill",
                    emphasized: true,
                    action: printReceipt
                )
                receiptActionButton(
                    title: Language.get("POS_Receipt_Share", alter: "مشاركة PDF"),
                    symbol: "square.and.arrow.up",
                    emphasized: false,
                    action: shareReceipt
                )
            }

            Button {
                dismiss()
            } label: {
                Text(Language.get("POS_Receipt_Done", alter: "تم"))
                    .font(Font.custom("Beiruti-Bold", size: 16, relativeTo: .callout))
                    .foregroundColor(AdminSurface.primaryText)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, 12)
        .padding(.bottom, 10)
        .background(.ultraThinMaterial)
        .overlay(alignment: .top) {
            Rectangle().fill(AdminSurface.hairline).frame(height: 1)
        }
    }

    private func receiptActionButton(
        title: String,
        symbol: String,
        emphasized: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Label(title, systemImage: symbol)
                .font(Font.custom("Beiruti-Bold", size: 16, relativeTo: .callout))
                .foregroundColor(emphasized ? .white : AdminSurface.primary)
                .frame(maxWidth: .infinity, minHeight: 48)
                .background(
                    emphasized ? AdminSurface.primary : AdminSurface.primary.opacity(0.10),
                    in: RoundedRectangle(cornerRadius: 15, style: .continuous)
                )
        }
        .accessibilityLabel(title)
    }

    private func printReceipt() {
        do {
            let data = try POSReceiptPDFExporter.pdfData(for: receipt)
            POSReceiptPrintCoordinator.present(data: data, receipt: receipt) { error in
                if error != nil {
                    feedbackMessage = Language.get(
                        "POS_Receipt_PrintFailed",
                        alter: "تعذرت طباعة الإيصال. يمكنك مشاركته كملف PDF بدلاً من ذلك."
                    )
                }
            }
        } catch {
            feedbackMessage = Language.get(
                "POS_Receipt_ExportFailed",
                alter: "تعذر إنشاء ملف الإيصال. حاول مرة أخرى."
            )
        }
    }

    private func shareReceipt() {
        removeTemporaryReceipt()
        do {
            temporaryReceiptURL = try POSReceiptPDFExporter.temporaryPDF(for: receipt)
            isSharing = temporaryReceiptURL != nil
        } catch {
            feedbackMessage = Language.get(
                "POS_Receipt_ExportFailed",
                alter: "تعذر إنشاء ملف الإيصال. حاول مرة أخرى."
            )
        }
    }

    private func removeTemporaryReceipt() {
        if let temporaryReceiptURL {
            try? FileManager.default.removeItem(at: temporaryReceiptURL)
        }
        temporaryReceiptURL = nil
        isSharing = false
    }
}

// MARK: - Localized Formatting

@MainActor
private enum POSReceiptFormat {
    static func currency(_ value: Double, code: String) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = code.isEmpty ? "QAR" : code
        formatter.locale = Locale(identifier: Language.isRTL() ? "ar_QA" : "en_QA")
        return formatter.string(from: NSNumber(value: value))
            ?? String(format: "%.2f %@", value, code.isEmpty ? "QAR" : code)
    }

    static func date(_ value: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        formatter.locale = Locale(identifier: Language.isRTL() ? "ar_QA" : "en_QA")
        return formatter.string(from: value)
    }

    static func paymentMethod(_ value: String) -> String {
        switch value.lowercased() {
        case "cash": return Language.get("POS_Cash", alter: "نقدي")
        case "card": return Language.get("POS_Card", alter: "بطاقة")
        default: return value.isEmpty ? Language.get("POS_Receipt_NotAvailable", alter: "غير متاح") : value
        }
    }
}

// MARK: - PDF

private enum POSReceiptExportError: Error {
    case emptyDocument
}

@MainActor
private enum POSReceiptPDFExporter {
    static func pdfData(for receipt: POSCompletedReceipt) throws -> Data {
        let receiptWidth: CGFloat = 340.0
        let margin: CGFloat = 20.0
        let contentWidth = receiptWidth - (margin * 2)
        let rtl = Language.isRTL()

        // Fonts
        let brandFont = UIFont(name: "Beiruti-Bold", size: 20) ?? UIFont.boldSystemFont(ofSize: 20)
        let titleFont = UIFont(name: "Beiruti-Medium", size: 13) ?? UIFont.systemFont(ofSize: 13, weight: .medium)
        let headerFont = UIFont(name: "Beiruti-Bold", size: 13) ?? UIFont.boldSystemFont(ofSize: 13)
        let bodyFont = UIFont(name: "Beiruti-Regular", size: 11.5) ?? UIFont.systemFont(ofSize: 11.5)
        let boldBodyFont = UIFont(name: "Beiruti-Bold", size: 11.5) ?? UIFont.boldSystemFont(ofSize: 11.5)
        let totalTitleFont = UIFont(name: "Beiruti-Bold", size: 16) ?? UIFont.boldSystemFont(ofSize: 16)
        let totalAmountFont = UIFont(name: "Beiruti-Bold", size: 20) ?? UIFont.boldSystemFont(ofSize: 20)
        let footerFont = UIFont(name: "Beiruti-Medium", size: 11) ?? UIFont.systemFont(ofSize: 11, weight: .medium)
        let microFont = UIFont(name: "Beiruti-Regular", size: 8.5) ?? UIFont.systemFont(ofSize: 8.5)

        // Colors
        let primaryColor = UIColor(red: 0.49, green: 0.06, blue: 0.20, alpha: 1.0)
        let textColor = UIColor(red: 0.12, green: 0.10, blue: 0.11, alpha: 1.0)
        let secondaryColor = UIColor(red: 0.46, green: 0.42, blue: 0.44, alpha: 1.0)
        let lineColor = UIColor(red: 0.88, green: 0.84, blue: 0.86, alpha: 1.0)

        // Paragraph styles
        let centerStyle = NSMutableParagraphStyle()
        centerStyle.alignment = .center
        centerStyle.baseWritingDirection = rtl ? .rightToLeft : .leftToRight

        let leadingStyle = NSMutableParagraphStyle()
        leadingStyle.alignment = rtl ? .right : .left
        leadingStyle.baseWritingDirection = rtl ? .rightToLeft : .leftToRight

        let trailingStyle = NSMutableParagraphStyle()
        trailingStyle.alignment = rtl ? .left : .right
        trailingStyle.baseWritingDirection = rtl ? .rightToLeft : .leftToRight

        // Measure dynamic height
        var dynamicHeight: CGFloat = margin

        // Logo
        let logoImage = UIImage(named: "LogoV5") ?? UIImage(named: "AD_LOGO")
        if logoImage != nil {
            dynamicHeight += 50.0 + 8.0
        }

        // Brand + Subtitle
        dynamicHeight += 26.0 + 18.0 + 12.0

        // Metadata rows
        dynamicHeight += (4 * 18.0) + 12.0

        // Items Header
        dynamicHeight += 20.0

        // Items
        for line in receipt.lines {
            let itemTextHeight: CGFloat = line.ringTags.isEmpty ? 22.0 : 34.0
            dynamicHeight += itemTextHeight + 4.0
        }
        dynamicHeight += 12.0

        // Totals
        var totalRowCount = 2
        if receipt.discount > 0 { totalRowCount += 1 }
        if receipt.paymentMethod.lowercased() == "cash" { totalRowCount += 2 }
        dynamicHeight += CGFloat(totalRowCount - 1) * 18.0 + 30.0 + 12.0

        // Customer details if present
        if !receipt.customerName.isEmpty || !receipt.customerPhone.isEmpty || !receipt.note.isEmpty {
            dynamicHeight += 50.0
        }

        // Footer
        dynamicHeight += 22.0 + 32.0 + 16.0 + margin

        let totalPageHeight = max(dynamicHeight, 350.0)
        let pageBounds = CGRect(x: 0, y: 0, width: receiptWidth, height: totalPageHeight)

        let rendererFormat = UIGraphicsPDFRendererFormat()
        rendererFormat.documentInfo = [
            kCGPDFContextCreator as String: "Pure Pets Admin",
            kCGPDFContextTitle as String: "\(Language.get("POS_Receipt_Title", alter: "إيصال بيع")) #\(receipt.transactionID)"
        ]

        let pdfRenderer = UIGraphicsPDFRenderer(bounds: pageBounds, format: rendererFormat)

        let data = pdfRenderer.pdfData { context in
            let w = receiptWidth
            let m = margin
            let cw = contentWidth

            context.beginPage()
            let cgContext = context.cgContext

            // White background
            cgContext.setFillColor(UIColor.white.cgColor)
            cgContext.fill(pageBounds)

            var currentY: CGFloat = m

            // 1. Draw Logo
            if let logo = logoImage {
                let logoSize: CGFloat = 48.0
                let logoRect = CGRect(x: (w - logoSize) / 2.0, y: currentY, width: logoSize, height: logoSize)
                logo.draw(in: logoRect)
                currentY += logoSize + 8.0
            }

            // 2. Brand Name
            let brandString = Language.isRTL() ? "بيور بتس" : "PURE PETS"
            let brandAttr: [NSAttributedString.Key: Any] = [
                .font: brandFont,
                .foregroundColor: textColor,
                .paragraphStyle: centerStyle
            ]
            let brandRect = CGRect(x: m, y: currentY, width: cw, height: 24.0)
            brandString.draw(in: brandRect, withAttributes: brandAttr)
            currentY += 24.0

            // 3. Title "إيصال بيع"
            let titleString = Language.get("POS_Receipt_Title", alter: "إيصال بيع")
            let titleAttr: [NSAttributedString.Key: Any] = [
                .font: titleFont,
                .foregroundColor: secondaryColor,
                .paragraphStyle: centerStyle
            ]
            let titleRect = CGRect(x: m, y: currentY, width: cw, height: 18.0)
            titleString.draw(in: titleRect, withAttributes: titleAttr)
            currentY += 22.0

            // Helper to draw dashed line
            func drawDashedSeparator(y: CGFloat) {
                cgContext.saveGState()
                cgContext.setStrokeColor(lineColor.cgColor)
                cgContext.setLineWidth(0.8)
                let dashes: [CGFloat] = [4.0, 3.0]
                cgContext.setLineDash(phase: 0, lengths: dashes)
                cgContext.move(to: CGPoint(x: m, y: y))
                cgContext.addLine(to: CGPoint(x: w - m, y: y))
                cgContext.strokePath()
                cgContext.restoreGState()
            }

            // Helper to draw solid line
            func drawSolidSeparator(y: CGFloat) {
                cgContext.saveGState()
                cgContext.setStrokeColor(lineColor.cgColor)
                cgContext.setLineWidth(0.5)
                cgContext.move(to: CGPoint(x: m, y: y))
                cgContext.addLine(to: CGPoint(x: w - m, y: y))
                cgContext.strokePath()
                cgContext.restoreGState()
            }

            // Helper to draw key-value row
            func drawRow(
                label: String,
                value: String,
                labelFont: UIFont? = nil,
                valueFont: UIFont? = nil,
                labelColor: UIColor? = nil,
                valueColor: UIColor? = nil,
                y: CGFloat,
                height: CGFloat = 16.0
            ) {
                let actualLabelFont = labelFont ?? bodyFont
                let actualValueFont = valueFont ?? boldBodyFont
                let actualLabelColor = labelColor ?? secondaryColor
                let actualValueColor = valueColor ?? textColor

                let halfWidth = cw * 0.52
                let valWidth = cw * 0.48

                let labelAttr: [NSAttributedString.Key: Any] = [
                    .font: actualLabelFont,
                    .foregroundColor: actualLabelColor,
                    .paragraphStyle: leadingStyle
                ]
                let valAttr: [NSAttributedString.Key: Any] = [
                    .font: actualValueFont,
                    .foregroundColor: actualValueColor,
                    .paragraphStyle: trailingStyle
                ]

                if rtl {
                    let labelRect = CGRect(x: w - m - halfWidth, y: y, width: halfWidth, height: height)
                    let valRect = CGRect(x: m, y: y, width: valWidth, height: height)
                    label.draw(in: labelRect, withAttributes: labelAttr)
                    value.draw(in: valRect, withAttributes: valAttr)
                } else {
                    let labelRect = CGRect(x: m, y: y, width: halfWidth, height: height)
                    let valRect = CGRect(x: m + halfWidth, y: y, width: valWidth, height: height)
                    label.draw(in: labelRect, withAttributes: labelAttr)
                    value.draw(in: valRect, withAttributes: valAttr)
                }
            }

            // 4. Metadata rows
            drawRow(label: Language.get("POS_Receipt_Transaction", alter: "رقم المعاملة"), value: receipt.transactionID, y: currentY)
            currentY += 16.0
            drawRow(label: Language.get("POS_Receipt_Date", alter: "التاريخ"), value: POSReceiptFormat.date(receipt.createdAt), y: currentY)
            currentY += 16.0
            drawRow(label: Language.get("POS_Receipt_Payment", alter: "طريقة الدفع"), value: POSReceiptFormat.paymentMethod(receipt.paymentMethod), y: currentY)
            currentY += 16.0
            drawRow(label: Language.get("POS_Receipt_Status", alter: "الحالة"), value: Language.get("POS_Receipt_Completed", alter: "مكتملة"), y: currentY)
            currentY += 20.0

            drawDashedSeparator(y: currentY)
            currentY += 8.0

            // 5. Items Header
            let itemsHeader = Language.get("POS_Receipt_Items", alter: "العناصر")
            let itemsHeaderAttr: [NSAttributedString.Key: Any] = [
                .font: headerFont,
                .foregroundColor: secondaryColor,
                .paragraphStyle: leadingStyle
            ]
            itemsHeader.draw(in: CGRect(x: m, y: currentY, width: cw, height: 16.0), withAttributes: itemsHeaderAttr)
            currentY += 18.0

            // 6. Items list
            for line in receipt.lines {
                let qtyStr = "\(line.quantity)×"
                let priceStr = POSReceiptFormat.currency(line.lineTotal, code: receipt.currency)

                let qtyWidth: CGFloat = 24.0
                let priceWidth: CGFloat = 75.0
                let nameWidth = cw - qtyWidth - priceWidth - 8.0

                let qtyAttr: [NSAttributedString.Key: Any] = [
                    .font: boldBodyFont,
                    .foregroundColor: primaryColor,
                    .paragraphStyle: leadingStyle
                ]
                let nameAttr: [NSAttributedString.Key: Any] = [
                    .font: boldBodyFont,
                    .foregroundColor: textColor,
                    .paragraphStyle: leadingStyle
                ]
                let priceAttr: [NSAttributedString.Key: Any] = [
                    .font: boldBodyFont,
                    .foregroundColor: textColor,
                    .paragraphStyle: trailingStyle
                ]

                if rtl {
                    qtyStr.draw(in: CGRect(x: w - m - qtyWidth, y: currentY, width: qtyWidth, height: 16.0), withAttributes: qtyAttr)
                    line.name.draw(in: CGRect(x: m + priceWidth + 4.0, y: currentY, width: nameWidth, height: 16.0), withAttributes: nameAttr)
                    priceStr.draw(in: CGRect(x: m, y: currentY, width: priceWidth, height: 16.0), withAttributes: priceAttr)
                } else {
                    qtyStr.draw(in: CGRect(x: m, y: currentY, width: qtyWidth, height: 16.0), withAttributes: qtyAttr)
                    line.name.draw(in: CGRect(x: m + qtyWidth + 4.0, y: currentY, width: nameWidth, height: 16.0), withAttributes: nameAttr)
                    priceStr.draw(in: CGRect(x: w - m - priceWidth, y: currentY, width: priceWidth, height: 16.0), withAttributes: priceAttr)
                }
                currentY += 16.0

                if !line.ringTags.isEmpty {
                    let tagsStr = Language.get("POS_Receipt_Rings", alter: "الوسوم") + ": " + line.ringTags.joined(separator: ", ")
                    let tagAttr: [NSAttributedString.Key: Any] = [
                        .font: microFont,
                        .foregroundColor: secondaryColor,
                        .paragraphStyle: leadingStyle
                    ]
                    let tagX = rtl ? (m + priceWidth + 4.0) : (m + qtyWidth + 4.0)
                    tagsStr.draw(in: CGRect(x: tagX, y: currentY, width: nameWidth, height: 12.0), withAttributes: tagAttr)
                    currentY += 14.0
                }
                currentY += 2.0
            }

            currentY += 4.0
            drawDashedSeparator(y: currentY)
            currentY += 8.0

            // 7. Totals
            drawRow(label: Language.get("POS_Receipt_Subtotal", alter: "المجموع الفرعي"), value: POSReceiptFormat.currency(receipt.subtotal, code: receipt.currency), y: currentY)
            currentY += 16.0

            if receipt.discount > 0 {
                drawRow(label: Language.get("POS_Receipt_Discount", alter: "الخصم"), value: "−" + POSReceiptFormat.currency(receipt.discount, code: receipt.currency), valueColor: primaryColor, y: currentY)
                currentY += 16.0
            }

            // Grand Total (Large & Maroon)
            let grandLabel = Language.get("POS_Receipt_Total", alter: "الإجمالي")
            let grandVal = POSReceiptFormat.currency(receipt.total, code: receipt.currency)

            let grandLabelAttr: [NSAttributedString.Key: Any] = [
                .font: totalTitleFont,
                .foregroundColor: textColor,
                .paragraphStyle: leadingStyle
            ]
            let grandValAttr: [NSAttributedString.Key: Any] = [
                .font: totalAmountFont,
                .foregroundColor: primaryColor,
                .paragraphStyle: trailingStyle
            ]

            let grandHalf = cw * 0.4
            let grandValW = cw * 0.6
            if rtl {
                grandLabel.draw(in: CGRect(x: w - m - grandHalf, y: currentY, width: grandHalf, height: 26.0), withAttributes: grandLabelAttr)
                grandVal.draw(in: CGRect(x: m, y: currentY, width: grandValW, height: 26.0), withAttributes: grandValAttr)
            } else {
                grandLabel.draw(in: CGRect(x: m, y: currentY, width: grandHalf, height: 26.0), withAttributes: grandLabelAttr)
                grandVal.draw(in: CGRect(x: m + grandHalf, y: currentY, width: grandValW, height: 26.0), withAttributes: grandValAttr)
            }
            currentY += 26.0

            if receipt.paymentMethod.lowercased() == "cash" {
                drawRow(label: Language.get("POS_Receipt_CashReceived", alter: "المبلغ المستلم"), value: POSReceiptFormat.currency(receipt.cashReceived, code: receipt.currency), y: currentY)
                currentY += 16.0
                drawRow(label: Language.get("POS_Receipt_ChangeDue", alter: "الباقي"), value: POSReceiptFormat.currency(receipt.changeDue, code: receipt.currency), y: currentY)
                currentY += 16.0
            }

            // 8. Customer Details if present
            if !receipt.customerName.isEmpty || !receipt.customerPhone.isEmpty || !receipt.note.isEmpty {
                currentY += 4.0
                drawSolidSeparator(y: currentY)
                currentY += 8.0
                if !receipt.customerName.isEmpty {
                    drawRow(label: Language.get("POS_Receipt_Customer", alter: "العميل"), value: receipt.customerName, y: currentY)
                    currentY += 16.0
                }
                if !receipt.customerPhone.isEmpty {
                    drawRow(label: Language.get("POS_Receipt_Phone", alter: "الهاتف"), value: receipt.customerPhone, y: currentY)
                    currentY += 16.0
                }
                if !receipt.note.isEmpty {
                    let noteTitle = Language.get("POS_Receipt_Notes", alter: "ملاحظات") + ": " + receipt.note
                    let noteAttr: [NSAttributedString.Key: Any] = [
                        .font: microFont,
                        .foregroundColor: secondaryColor,
                        .paragraphStyle: leadingStyle
                    ]
                    noteTitle.draw(in: CGRect(x: m, y: currentY, width: cw, height: 24.0), withAttributes: noteAttr)
                    currentY += 20.0
                }
            }

            currentY += 10.0

            // 9. Thank You Note
            let thanksStr = Language.get("POS_Receipt_ThankYou", alter: "شكرًا لاختياركم بيوربيتس")
            let thanksAttr: [NSAttributedString.Key: Any] = [
                .font: footerFont,
                .foregroundColor: primaryColor,
                .paragraphStyle: centerStyle
            ]
            thanksStr.draw(in: CGRect(x: m, y: currentY, width: cw, height: 18.0), withAttributes: thanksAttr)
            currentY += 20.0

            // 10. Contact & Support Info
            let urlStr = "https://pure-pets.net"
            let contactAttr: [NSAttributedString.Key: Any] = [
                .font: microFont,
                .foregroundColor: secondaryColor,
                .paragraphStyle: centerStyle
            ]
            urlStr.draw(in: CGRect(x: m, y: currentY, width: cw, height: 12.0), withAttributes: contactAttr)
            currentY += 13.0

            let supportStr = "support@pure-pets.net  •  +974 5999 7720"
            supportStr.draw(in: CGRect(x: m, y: currentY, width: cw, height: 12.0), withAttributes: contactAttr)
            currentY += 16.0

            // 11. Footer Tx ID
            let txFooter = "#" + receipt.transactionID
            txFooter.draw(in: CGRect(x: m, y: currentY, width: cw, height: 14.0), withAttributes: contactAttr)
        }

        guard data.count > 0 else { throw POSReceiptExportError.emptyDocument }
        return data
    }

    static func temporaryPDF(for receipt: POSCompletedReceipt) throws -> URL {
        let shortID = String(receipt.transactionID.prefix(12))
        let safeID = shortID.replacingOccurrences(
            of: "[^A-Za-z0-9_-]",
            with: "-",
            options: .regularExpression
        )
        let fileName = "PurePets-Receipt-\(safeID)-\(UUID().uuidString.prefix(6)).pdf"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
        let data = try pdfData(for: receipt)
        try data.write(to: url, options: .atomic)
        return url
    }
}

// MARK: - Native Print / Share

@MainActor
private enum POSReceiptPrintCoordinator {
    static func present(
        data: Data,
        receipt: POSCompletedReceipt,
        completion: @escaping (Error?) -> Void
    ) {
        guard UIPrintInteractionController.isPrintingAvailable else {
            completion(POSReceiptExportError.emptyDocument)
            return
        }

        let controller = UIPrintInteractionController.shared
        let info = UIPrintInfo(dictionary: nil)
        info.outputType = .general
        info.jobName = "\(Language.get("POS_Receipt_Title", alter: "إيصال بيع")) #\(receipt.transactionID.prefix(10))"
        controller.printInfo = info
        controller.printingItem = data

        guard let presenter = topViewController() else {
            completion(POSReceiptExportError.emptyDocument)
            return
        }
        if UIDevice.current.userInterfaceIdiom == .pad {
            controller.present(from: presenter.view.bounds, in: presenter.view, animated: true) { _, _, error in
                completion(error)
            }
        } else {
            controller.present(animated: true) { _, _, error in
                completion(error)
            }
        }
    }

    private static func topViewController(from root: UIViewController? = keyWindow?.rootViewController) -> UIViewController? {
        if let presented = root?.presentedViewController {
            return topViewController(from: presented)
        }
        if let navigation = root as? UINavigationController {
            return topViewController(from: navigation.visibleViewController)
        }
        if let tabs = root as? UITabBarController {
            return topViewController(from: tabs.selectedViewController)
        }
        return root
    }

    private static var keyWindow: UIWindow? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first { $0.isKeyWindow }
    }
}

private struct POSReceiptShareSheet: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [url], applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
