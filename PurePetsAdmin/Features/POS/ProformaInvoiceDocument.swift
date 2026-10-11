//
//  ProformaInvoiceDocument.swift
//  PurePetsAdmin
//
//  Print-only projection of an authoritative saved proforma. This layer never
//  calculates a sale, writes inventory, or changes invoice status.
//

import Foundation
import SwiftUI
import UIKit
import PDFKit
import CoreText

struct PPProformaPDFLine: Sendable {
    let title: String
    let code: String
    let unit: String
    let quantity: Decimal
    let unitPrice: Decimal
    let discount: Decimal
    let tax: Decimal
    let total: Decimal

    init(title: String, code: String = "", unit: String = "", quantity: Decimal,
         unitPrice: Decimal, discount: Decimal, tax: Decimal, total: Decimal) {
        self.title = title
        self.code = code
        self.unit = unit
        self.quantity = quantity
        self.unitPrice = unitPrice
        self.discount = discount
        self.tax = tax
        self.total = total
    }
}

struct PPProformaPDFSnapshot: Sendable {
    let id: String
    let number: String
    let revision: Int
    let status: String
    let statusTitle: String
    let branchName: String
    let currency: String
    let currencyDigits: Int
    let customerName: String
    let customerPhone: String
    let customerEmail: String
    let validUntil: Date?
    let issuedAt: Date
    let notes: String
    let lines: [PPProformaPDFLine]
    let subtotal: Decimal
    let discount: Decimal
    let tax: Decimal
    let total: Decimal

    init(id: String, number: String, revision: Int, status: String, statusTitle: String,
         branchName: String, currency: String, currencyDigits: Int = 2,
         customerName: String, customerPhone: String = "", customerEmail: String = "",
         validUntil: Date?, issuedAt: Date, notes: String = "", lines: [PPProformaPDFLine],
         subtotal: Decimal, discount: Decimal, tax: Decimal, total: Decimal) {
        self.id = id
        self.number = number
        self.revision = revision
        self.status = status
        self.statusTitle = statusTitle
        self.branchName = branchName
        self.currency = currency
        self.currencyDigits = currencyDigits
        self.customerName = customerName
        self.customerPhone = customerPhone
        self.customerEmail = customerEmail
        self.validUntil = validUntil
        self.issuedAt = issuedAt
        self.notes = notes
        self.lines = lines
        self.subtotal = subtotal
        self.discount = discount
        self.tax = tax
        self.total = total
    }
}

enum PPProformaPDFError: LocalizedError {
    case invalidSnapshot
    case renderingFailed
    case temporaryFileFailed

    var errorDescription: String? {
        let key: String
        switch self {
        case .invalidSnapshot: key = "Proforma_PDF_Error_Snapshot"
        case .renderingFailed: key = "Proforma_PDF_Error_Render"
        case .temporaryFileFailed: key = "Proforma_PDF_Error_File"
        }
        return Language.get(key, alter: nil)
    }
}

/// Own this object for the entire preview/share presentation. Its unique folder
/// cannot collide with another export; releasing the last owner removes it.
@MainActor
final class PPProformaPDFDocument: Identifiable {
    let id = UUID()
    let url: URL
    let number: String
    private let directoryURL: URL

    init(data: Data, number: String) throws {
        guard data.starts(with: Data("%PDF-".utf8)), PDFDocument(data: data)?.pageCount ?? 0 > 0 else {
            throw PPProformaPDFError.renderingFailed
        }
        self.number = number
        directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("PPProforma-\(UUID().uuidString)", isDirectory: true)
        let safeNumber = number.unicodeScalars.filter {
            CharacterSet.alphanumerics.contains($0) || $0 == "-" || $0 == "_"
        }.prefix(80).map(String.init).joined()
        url = directoryURL.appendingPathComponent("\(safeNumber.isEmpty ? "Proforma" : safeNumber).pdf")
        do {
            try FileManager.default.createDirectory(
                at: directoryURL, withIntermediateDirectories: true,
                attributes: [.protectionKey: FileProtectionType.complete]
            )
            try data.write(to: url, options: [.atomic, .completeFileProtection])
        } catch {
            try? FileManager.default.removeItem(at: directoryURL)
            throw PPProformaPDFError.temporaryFileFailed
        }
    }

    func cleanup() {
        try? FileManager.default.removeItem(at: directoryURL)
    }

    deinit {
        try? FileManager.default.removeItem(at: directoryURL)
    }
}

/// Native PDFKit keeps text selectable, searchable and vector-sharp at any zoom.
@MainActor
struct PPProformaPDFPreview: UIViewRepresentable {
    let data: Data

    func makeUIView(context: Context) -> PDFView {
        let view = PDFView()
        view.backgroundColor = .ppBackgroundSecondary
        view.autoScales = true
        view.displayMode = .singlePageContinuous
        view.displayDirection = .vertical
        view.displaysPageBreaks = true
        view.semanticContentAttribute = .forceLeftToRight
        view.accessibilityLabel = Language.get("Proforma_PDF_Preview", alter: nil)
        view.document = PDFDocument(data: data)
        context.coordinator.data = data
        return view
    }

    func updateUIView(_ view: PDFView, context: Context) {
        guard context.coordinator.data != data else { return }
        let previousPage = view.currentPage.flatMap { view.document?.index(for: $0) } ?? 0
        view.document = PDFDocument(data: data)
        if let page = view.document?.page(at: min(previousPage, max(0, (view.document?.pageCount ?? 1) - 1))) {
            view.go(to: page)
        }
        context.coordinator.data = data
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator {
        var data: Data?
    }
}

/// Sharing requires a user-selected destination. The coordinator retains the
/// PDF owner until the native activity sheet has finished reading its URL.
@MainActor
struct PPProformaPDFShareSheet: UIViewControllerRepresentable {
    let document: PPProformaPDFDocument

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let message = String(
            format: Language.get("Proforma_PDF_Share_Message", alter: nil),
            document.number
        )
        let controller = UIActivityViewController(activityItems: [document.url, message], applicationActivities: nil)
        if let popover = controller.popoverPresentationController {
            popover.sourceView = controller.view
            popover.sourceRect = CGRect(x: 0, y: 0, width: 1, height: 1)
            popover.permittedArrowDirections = []
        }
        return controller
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator(document: document) }

    final class Coordinator {
        let document: PPProformaPDFDocument
        init(document: PPProformaPDFDocument) { self.document = document }
    }
}

/// Native printing via UIPrintInteractionController without requiring modal dismissal.
@MainActor
enum PPProformaPDFPrinter {
    static func print(data: Data, jobName: String, completion: ((Error?) -> Void)? = nil) {
        guard UIPrintInteractionController.isPrintingAvailable else {
            completion?(PPProformaPDFError.renderingFailed)
            return
        }
        let controller = UIPrintInteractionController.shared
        let info = UIPrintInfo(dictionary: nil)
        info.outputType = .general
        info.jobName = jobName
        controller.printInfo = info
        controller.printingItem = data

        guard let presenter = topViewController() else {
            completion?(PPProformaPDFError.renderingFailed)
            return
        }
        if UIDevice.current.userInterfaceIdiom == .pad {
            controller.present(from: presenter.view.bounds, in: presenter.view, animated: true) { _, _, error in
                completion?(error)
            }
        } else {
            controller.present(animated: true) { _, _, error in
                completion?(error)
            }
        }
    }

    private static func topViewController(from root: UIViewController? = keyWindow?.rootViewController) -> UIViewController? {
        if let presented = root?.presentedViewController {
            return topViewController(from: presented)
        }
        if let navigation = root as? UINavigationController {
            return topViewController(from: navigation.visibleViewController ?? navigation.topViewController)
        }
        if let tabs = root as? UITabBarController {
            return topViewController(from: tabs.selectedViewController)
        }
        return root
    }

    private static var keyWindow: UIWindow? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }?
            .windows.first { $0.isKeyWindow }
            ?? UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .first?.windows.first
    }
}

@MainActor
enum PPProformaPDFRenderer {
    static func render(snapshot: PPProformaPDFSnapshot) throws -> Data {
        try validate(snapshot)
        let composer = PPProformaPDFComposer(snapshot: snapshot, isRTL: Language.isRTL())
        let pages = try composer.compose()
        let format = UIGraphicsPDFRendererFormat()
        format.documentInfo = [
            kCGPDFContextCreator as String: "Pure Pets Admin",
            kCGPDFContextTitle as String: "\(Language.get("Proforma_PDF_Title", alter: nil)) \(snapshot.number)",
            kCGPDFContextSubject as String: Language.get("Proforma_PDF_Nonbinding", alter: nil)
        ]
        let renderer = UIGraphicsPDFRenderer(bounds: composer.pageBounds, format: format)
        let data = renderer.pdfData { context in
            for (index, commands) in pages.enumerated() {
                context.beginPage()
                context.cgContext.setFillColor(UIColor.white.cgColor)
                context.cgContext.fill(composer.pageBounds)
                commands.forEach { $0.draw(in: context.cgContext) }
                composer.drawFooter(page: index + 1, pageCount: pages.count, context: context.cgContext)
            }
        }
        guard let document = PDFDocument(data: data), document.pageCount == pages.count, !pages.isEmpty else {
            throw PPProformaPDFError.renderingFailed
        }
        return data
    }

    private static func validate(_ snapshot: PPProformaPDFSnapshot) throws {
        let allMoney = [snapshot.subtotal, snapshot.discount, snapshot.tax, snapshot.total]
            + snapshot.lines.flatMap { [$0.quantity, $0.unitPrice, $0.discount, $0.tax, $0.total] }
        let textSize = snapshot.lines.reduce(0) { $0 + $1.title.utf16.count + $1.code.utf16.count + $1.unit.utf16.count }
            + snapshot.notes.utf16.count + snapshot.customerName.utf16.count
            + snapshot.customerPhone.utf16.count + snapshot.customerEmail.utf16.count
            + snapshot.branchName.utf16.count
        guard !snapshot.number.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              snapshot.number.utf16.count <= 100, snapshot.revision > 0,
              (0...4).contains(snapshot.currencyDigits),
              snapshot.currency.range(of: "^[A-Z]{3}$", options: .regularExpression) != nil,
              !snapshot.lines.isEmpty, snapshot.lines.count <= 1_000,
              textSize <= 200_000, snapshot.statusTitle.utf16.count <= 150,
              snapshot.issuedAt.timeIntervalSince1970.isFinite,
              snapshot.validUntil?.timeIntervalSince1970.isFinite ?? true,
              allMoney.allSatisfy({ !$0.isNaN && $0 >= 0 }),
              snapshot.lines.allSatisfy({ $0.quantity > 0 && !$0.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) else {
            throw PPProformaPDFError.invalidSnapshot
        }
    }
}

// MARK: - Measured, bounded A4 page composition

@MainActor
private enum PPProformaPDFCommand {
    case text(NSAttributedString, CGRect)
    case fill(CGRect, UIColor)
    case rule(CGRect, UIColor)
    case image(UIImage, CGRect)

    func draw(in context: CGContext) {
        switch self {
        case let .text(text, rect):
            context.saveGState()
            context.textMatrix = .identity
            context.translateBy(x: rect.minX, y: rect.maxY)
            context.scaleBy(x: 1, y: -1)
            let path = CGPath(rect: CGRect(origin: .zero, size: rect.size), transform: nil)
            let framesetter = CTFramesetterCreateWithAttributedString(text as CFAttributedString)
            CTFrameDraw(CTFramesetterCreateFrame(framesetter, CFRange(location: 0, length: text.length), path, nil), context)
            context.restoreGState()
        case let .fill(rect, color), let .rule(rect, color):
            context.setFillColor(color.cgColor)
            context.fill(rect)
        case let .image(image, rect):
            context.saveGState()
            UIGraphicsPushContext(context)
            image.draw(in: rect)
            UIGraphicsPopContext()
            context.restoreGState()
        }
    }
}

@MainActor
private final class PPProformaPDFComposer {
    let pageBounds = CGRect(x: 0, y: 0, width: 595.28, height: 841.89)
    private let margin: CGFloat = 34
    private let bottom: CGFloat = 765
    private let rose = UIColor(red: 0.72, green: 0.08, blue: 0.27, alpha: 1)
    private let ink = UIColor(white: 0.13, alpha: 1)
    private let secondary = UIColor(white: 0.38, alpha: 1)
    private let hairline = UIColor(white: 0.88, alpha: 1)
    private let rowTint = UIColor(white: 0.975, alpha: 1)
    private let snapshot: PPProformaPDFSnapshot
    private let isRTL: Bool
    private var pages: [[PPProformaPDFCommand]] = []
    private var y: CGFloat = 0
    private var repeatingColumns = false
    private var width: CGFloat { pageBounds.width - 2 * margin }

    init(snapshot: PPProformaPDFSnapshot, isRTL: Bool) {
        self.snapshot = snapshot
        self.isRTL = isRTL
    }

    func compose() throws -> [[PPProformaPDFCommand]] {
        try startPage()
        try metadataBar()
        try heading("Proforma_PDF_Customer")
        try flow(text(snapshot.customerName.isEmpty ? loc("Proforma_PDF_UnnamedCustomer") : snapshot.customerName, size: 13, bold: true))
        if !snapshot.customerPhone.isEmpty { try flow(text(snapshot.customerPhone, size: 11, technical: true)) }
        if !snapshot.customerEmail.isEmpty { try flow(text(snapshot.customerEmail, size: 11, technical: true)) }
        y += 15
        try heading("Proforma_PDF_Items")
        repeatingColumns = true
        try columnHeader()
        for (index, line) in snapshot.lines.enumerated() { try item(line, index: index) }
        repeatingColumns = false
        y += 15
        try totals()
        if !snapshot.notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            y += 16
            try heading("Proforma_PDF_Notes")
            try flow(text(snapshot.notes, size: 11))
        }
        y += 16
        try flow(text(loc("Proforma_PDF_Nonbinding_Detail"), size: 10, color: secondary))
        return pages
    }

    private func startPage() throws {
        guard pages.count < 200 else { throw PPProformaPDFError.renderingFailed }
        pages.append([])
        y = margin

        let logo = UIImage(named: "LogoV5") ?? UIImage(named: "AD_LOGO")
        let logoSize: CGFloat = 72
        let logoX = isRTL ? margin : (margin + width - logoSize)
        let textX = isRTL ? (margin + logoSize + 20) : margin
        let textWidth = width - logoSize - 20

        if let logo = logo {
            append(.image(logo, CGRect(x: logoX, y: y + 2, width: logoSize, height: logoSize)))
        }

        let brand = text(loc("Proforma_PDF_Brand"), size: 23, bold: true, color: rose)
        let title = text(loc("Proforma_PDF_Title"), size: 17, bold: true)
        append(.text(brand, CGRect(x: textX, y: y, width: textWidth, height: 31)))
        y += 35
        append(.text(title, CGRect(x: textX, y: y, width: textWidth, height: 26)))
        y += 29
        let identity = text("\(snapshot.number)  ·  \(loc("Proforma_PDF_Revision")) \(snapshot.revision)", size: 10, color: secondary, technical: true)
        let identityHeight = measured(identity, width: textWidth)
        append(.text(identity, CGRect(x: textX, y: y, width: textWidth, height: identityHeight)))
        y += identityHeight + 4
        let state = text(snapshot.statusTitle, size: 11, bold: true, color: rose)
        let stateHeight = measured(state, width: textWidth)
        append(.text(state, CGRect(x: textX, y: y, width: textWidth, height: stateHeight)))
        y += stateHeight + 6
        let notice = text(loc("Proforma_PDF_Nonbinding"), size: 10, bold: true, color: secondary)
        let noticeHeight = measured(notice, width: textWidth)
        append(.text(notice, CGRect(x: textX, y: y, width: textWidth, height: noticeHeight)))
        y += noticeHeight + 10

        if logo != nil {
            y = max(y, margin + logoSize + 12)
        }

        append(.rule(CGRect(x: margin, y: y, width: width, height: 0.7), hairline))
        y += 14
        if repeatingColumns { try columnHeader() }
    }

    private func append(_ command: PPProformaPDFCommand) {
        pages[pages.count - 1].append(command)
    }

    private func ensure(_ height: CGFloat) throws {
        if y + height > bottom { try startPage() }
        guard height <= bottom - y else { throw PPProformaPDFError.renderingFailed }
    }

    private func heading(_ key: String) throws {
        let value = text(loc(key), size: 12, bold: true)
        let h = measured(value, width: width)
        try ensure(h + 25)
        append(.text(value, CGRect(x: margin, y: y, width: width, height: h)))
        y += h + 8
    }

    private func metadataBar() throws {
        struct MetaItem {
            let labelKey: String
            let value: String
            let technical: Bool
        }

        let items: [MetaItem] = [
            MetaItem(
                labelKey: "Proforma_PDF_Branch",
                value: snapshot.branchName.isEmpty ? loc("Proforma_PDF_NotProvided") : snapshot.branchName,
                technical: false
            ),
            MetaItem(
                labelKey: "Proforma_PDF_Issued",
                value: date(snapshot.issuedAt),
                technical: true
            ),
            MetaItem(
                labelKey: "Proforma_PDF_ValidUntil",
                value: snapshot.validUntil.map { date($0, dateOnly: true) } ?? loc("Proforma_PDF_NoValidity"),
                technical: snapshot.validUntil != nil
            ),
            MetaItem(
                labelKey: "Proforma_PDF_Currency",
                value: snapshot.currency.isEmpty ? loc("Proforma_PDF_NotProvided") : snapshot.currency,
                technical: true
            )
        ]

        let columnCount = CGFloat(items.count)
        let colWidth = width / columnCount
        let innerPadding: CGFloat = 8
        let availableWidth = colWidth - (innerPadding * 2)

        let prepared = items.map { item -> (labelAttr: NSAttributedString, valueAttr: NSAttributedString, labelH: CGFloat, valueH: CGFloat) in
            let labelAttr = text(loc(item.labelKey), size: 9, bold: true, color: secondary)
            let valueAttr = text(item.value, size: 11, bold: false, technical: item.technical)
            let labelH = measured(labelAttr, width: availableWidth)
            let valueH = measured(valueAttr, width: availableWidth)
            return (labelAttr, valueAttr, labelH, valueH)
        }

        let maxLabelH = prepared.map { $0.labelH }.max() ?? 14
        let maxValueH = prepared.map { $0.valueH }.max() ?? 16
        let labelValueSpacing: CGFloat = 3
        let verticalPadding: CGFloat = 8
        let barHeight = max(44, verticalPadding + maxLabelH + labelValueSpacing + maxValueH + verticalPadding)

        try ensure(barHeight + 10)

        // Subtle background container and borders
        append(.fill(CGRect(x: margin, y: y, width: width, height: barHeight), rowTint))
        append(.rule(CGRect(x: margin, y: y, width: width, height: 0.5), hairline))
        append(.rule(CGRect(x: margin, y: y + barHeight, width: width, height: 0.5), hairline))

        // Vertical dividers between columns
        for d in 1..<items.count {
            let divX = isRTL ? (margin + width - CGFloat(d) * colWidth) : (margin + CGFloat(d) * colWidth)
            append(.rule(CGRect(x: divX, y: y + 6, width: 0.5, height: barHeight - 12), hairline))
        }

        // Column contents
        for (index, col) in prepared.enumerated() {
            let colX = isRTL ? (margin + width - CGFloat(index + 1) * colWidth) : (margin + CGFloat(index) * colWidth)
            let textX = colX + innerPadding
            let labelY = y + verticalPadding
            let valueY = labelY + maxLabelH + labelValueSpacing
            append(.text(col.labelAttr, CGRect(x: textX, y: labelY, width: availableWidth, height: col.labelH)))
            append(.text(col.valueAttr, CGRect(x: textX, y: valueY, width: availableWidth, height: col.valueH)))
        }

        y += barHeight + 14
    }

    /// CoreText returns UTF-16 cluster boundaries. The exact same frame geometry
    /// is used for measuring and drawing, so long Arabic text is never truncated.
    private func flow(_ value: NSAttributedString) throws {
        var offset = 0
        while offset < value.length {
            if bottom - y < 26 { try startPage() }
            let remaining = value.attributedSubstring(from: NSRange(location: offset, length: value.length - offset))
            let fragment = try fittingFragment(remaining, width: width, height: bottom - y - 2)
            append(.text(fragment.text, CGRect(x: margin, y: y, width: width, height: fragment.height)))
            y += fragment.height + 3
            offset += fragment.text.length
            if offset < value.length { try startPage() }
        }
    }

    // Logical order is product, quantity, price, discount, tax, total. The
    // physical column positions mirror for Arabic; each decimal stays LTR.
    private var columnWidths: [CGFloat] { [width - 310, 42, 67, 67, 67, 67] }

    private func columnRect(_ index: Int, y: CGFloat, height: CGFloat) -> CGRect {
        let prior = columnWidths.prefix(index).reduce(0, +)
        let x = isRTL ? margin + width - prior - columnWidths[index] : margin + prior
        return CGRect(x: x + 6, y: y, width: columnWidths[index] - 12, height: height)
    }

    private func columnHeader() throws {
        let keys = ["Proforma_PDF_Item", "Proforma_PDF_Quantity", "Proforma_PDF_UnitPrice", "Proforma_PDF_Discount", "Proforma_PDF_Tax", "Proforma_PDF_LineTotal"]
        let values = keys.enumerated().map { index, key in
            text(loc(key), size: 9, bold: true, color: secondary, centered: index > 0)
        }
        let h = max(27, zip(values, columnWidths).map { measured($0.0, width: $0.1 - 12) + 12 }.max() ?? 27)
        // startPage calls this only after resetting y, avoiding recursive breaks.
        if y + h + 28 > bottom {
            let previouslyRepeating = repeatingColumns
            repeatingColumns = false
            try startPage()
            repeatingColumns = previouslyRepeating
        }
        append(.fill(CGRect(x: margin, y: y, width: width, height: h), UIColor(white: 0.95, alpha: 1)))
        for index in values.indices { append(.text(values[index], columnRect(index, y: y + 6, height: h - 10))) }
        y += h
    }

    private func item(_ line: PPProformaPDFLine, index: Int) throws {
        let title = NSMutableAttributedString(attributedString: text(line.title, size: 11, bold: true))
        if !line.code.isEmpty { title.append(text("\n\(line.code)", size: 9, color: secondary, technical: true)) }
        if !line.unit.isEmpty { title.append(text("\n\(line.unit)", size: 9, color: secondary)) }
        let numericValues = [
            number(line.quantity, digits: 0, maximumDigits: 6),
            number(line.unitPrice, digits: snapshot.currencyDigits, maximumDigits: max(4, snapshot.currencyDigits)),
            number(line.discount, digits: snapshot.currencyDigits),
            number(line.tax, digits: snapshot.currencyDigits),
            number(line.total, digits: snapshot.currencyDigits)
        ]
        let numeric = numericValues.map { text($0, size: 9.5, technical: true, centered: true) }
        let numberHeight = zip(numeric, columnWidths.dropFirst()).map { measured($0.0, width: $0.1 - 12) }.max() ?? 18
        var offset = 0
        while offset < title.length {
            try ensure(max(36, numberHeight + 16))
            let remaining = title.attributedSubstring(from: NSRange(location: offset, length: title.length - offset))
            let fragment = try fittingFragment(remaining, width: columnWidths[0] - 12, height: bottom - y - 16)
            let h = max(36, max(fragment.height, offset == 0 ? numberHeight : 0) + 16)
            if index.isMultiple(of: 2) { append(.fill(CGRect(x: margin, y: y, width: width, height: h), rowTint)) }
            append(.text(fragment.text, columnRect(0, y: y + 8, height: fragment.height)))
            if offset == 0 {
                for position in numeric.indices {
                    append(.text(numeric[position], columnRect(position + 1, y: y + 8, height: h - 14)))
                }
            } else {
                let continued = text(loc("Proforma_PDF_Continued"), size: 8, color: secondary, centered: true)
                append(.text(continued, columnRect(5, y: y + 8, height: h - 14)))
            }
            y += h
            offset += fragment.text.length
            if offset < title.length { try startPage() }
        }
        append(.rule(CGRect(x: margin, y: y, width: width, height: 0.4), hairline))
    }

    private func totals() throws {
        let rows: [(String, Decimal, Bool)] = [
            ("Proforma_PDF_Subtotal", snapshot.subtotal, false),
            ("Proforma_PDF_Discount", snapshot.discount, false),
            ("Proforma_PDF_Tax", snapshot.tax, false),
            ("Proforma_PDF_Total", snapshot.total, true)
        ]
        let labelWidth = width * 0.45
        let amountWidth = width - labelWidth - 16
        let prepared = rows.map { key, amount, prominent in
            let label = text(loc(key), size: prominent ? 14 : 11, bold: prominent)
            let value = text("\(number(amount, digits: snapshot.currencyDigits)) \(snapshot.currency)", size: prominent ? 15 : 11, bold: prominent, color: prominent ? rose : ink, technical: true, alignment: isRTL ? .left : .right)
            let h = max(prominent ? 43 : 28, max(measured(label, width: labelWidth), measured(value, width: amountWidth)) + 14)
            return (label, value, prominent, h)
        }
        try ensure(prepared.reduce(CGFloat.zero) { $0 + $1.3 })
        for (label, value, prominent, h) in prepared {
            if prominent { append(.fill(CGRect(x: margin, y: y, width: width, height: h), UIColor(red: 0.985, green: 0.95, blue: 0.96, alpha: 1))) }
            let labelX = isRTL ? margin + width - labelWidth - 8 : margin + 8
            let amountX = isRTL ? margin + 8 : margin + labelWidth
            append(.text(label, CGRect(x: labelX, y: y + 7, width: labelWidth, height: h - 10)))
            append(.text(value, CGRect(x: amountX, y: y + 7, width: amountWidth, height: h - 10)))
            y += h
        }
    }

    func drawFooter(page: Int, pageCount: Int, context: CGContext) {
        let label = String(format: loc("Proforma_PDF_Page"), page, pageCount)
        let footer = text(label, size: 9, color: secondary, centered: true)
        PPProformaPDFCommand.rule(CGRect(x: margin, y: 787, width: width, height: 0.5), hairline).draw(in: context)
        PPProformaPDFCommand.text(footer, CGRect(x: margin, y: 797, width: width, height: 18)).draw(in: context)
    }

    private func loc(_ key: String) -> String { Language.get(key, alter: nil) }

    private func text(_ value: String, size: CGFloat, bold: Bool = false, color: UIColor? = nil,
                      technical: Bool = false, centered: Bool = false, alignment: NSTextAlignment? = nil) -> NSAttributedString {
        let requestedAlignment = alignment ?? (centered ? .center : (isRTL ? .right : .left))
        var ctAlignment: CTTextAlignment = requestedAlignment == .center ? .center : (requestedAlignment == .right ? .right : .left)
        var direction: CTWritingDirection = technical ? .leftToRight : (isRTL ? .rightToLeft : .leftToRight)
        var breakMode: CTLineBreakMode = .byWordWrapping
        var lineSpacing: CGFloat = 2
        let paragraph = withUnsafePointer(to: &ctAlignment) { alignmentPointer in
            withUnsafePointer(to: &direction) { directionPointer in
                withUnsafePointer(to: &breakMode) { breakPointer in
                    withUnsafePointer(to: &lineSpacing) { spacingPointer in
                        let settings = [
                            CTParagraphStyleSetting(spec: .alignment, valueSize: MemoryLayout<CTTextAlignment>.size, value: alignmentPointer),
                            CTParagraphStyleSetting(spec: .baseWritingDirection, valueSize: MemoryLayout<CTWritingDirection>.size, value: directionPointer),
                            CTParagraphStyleSetting(spec: .lineBreakMode, valueSize: MemoryLayout<CTLineBreakMode>.size, value: breakPointer),
                            CTParagraphStyleSetting(spec: .lineSpacingAdjustment, valueSize: MemoryLayout<CGFloat>.size, value: spacingPointer)
                        ]
                        return CTParagraphStyleCreate(settings, settings.count)
                    }
                }
            }
        }
        let name = bold ? "Beiruti-Bold" : "Beiruti-Regular"
        let font = UIFont(name: name, size: size) ?? UIFont.systemFont(ofSize: size, weight: bold ? .bold : .regular)
        let ctFont = CTFontCreateWithName(font.fontName as CFString, font.pointSize, nil)
        // CTFrameDraw consumes CoreText's CF objects. Supplying UIKit-only
        // UIColor/paragraph attributes here can silently lose print styling.
        return NSAttributedString(string: value, attributes: [
            NSAttributedString.Key(kCTFontAttributeName as String): ctFont,
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): (color ?? ink).cgColor,
            NSAttributedString.Key(kCTParagraphStyleAttributeName as String): paragraph
        ])
    }

    private func measured(_ value: NSAttributedString, width: CGFloat) -> CGFloat {
        let framesetter = CTFramesetterCreateWithAttributedString(value as CFAttributedString)
        let size = CTFramesetterSuggestFrameSizeWithConstraints(framesetter, CFRange(location: 0, length: value.length), nil, CGSize(width: width, height: .greatestFiniteMagnitude), nil)
        return max(14, ceil(size.height) + 2)
    }

    private func fittingFragment(_ value: NSAttributedString, width: CGFloat, height: CGFloat) throws -> (text: NSAttributedString, height: CGFloat) {
        let framesetter = CTFramesetterCreateWithAttributedString(value as CFAttributedString)
        let path = CGPath(rect: CGRect(x: 0, y: 0, width: width, height: height), transform: nil)
        let frame = CTFramesetterCreateFrame(framesetter, CFRange(location: 0, length: value.length), path, nil)
        let range = CTFrameGetVisibleStringRange(frame)
        guard range.length > 0 else { throw PPProformaPDFError.renderingFailed }
        let fragment = value.attributedSubstring(from: NSRange(location: 0, length: range.length))
        let fragmentHeight = min(height, measured(fragment, width: width))
        let finalPath = CGPath(rect: CGRect(x: 0, y: 0, width: width, height: fragmentHeight), transform: nil)
        let finalFramesetter = CTFramesetterCreateWithAttributedString(fragment as CFAttributedString)
        let finalFrame = CTFramesetterCreateFrame(finalFramesetter, CFRange(location: 0, length: fragment.length), finalPath, nil)
        // Fail safely if a font fallback changes metrics between the suggested
        // frame and the final frame instead of exporting a truncated document.
        guard CTFrameGetVisibleStringRange(finalFrame).length == fragment.length else {
            throw PPProformaPDFError.renderingFailed
        }
        return (fragment, fragmentHeight)
    }

    private func number(_ value: Decimal, digits: Int, maximumDigits: Int? = nil) -> String {
        var input = value
        var rounded = Decimal()
        NSDecimalRound(&rounded, &input, maximumDigits ?? digits, .plain)
        let raw = NSDecimalNumber(decimal: rounded.isNaN ? value : rounded).stringValue
        // Keep base-10 digits throughout; NumberFormatter/Double can lose cents
        // for large NSDecimalNumber values. Expand exponent notation textually.
        let exponentParts = raw.lowercased().split(separator: "e", omittingEmptySubsequences: false)
        let mantissa = String(exponentParts[0])
        let exponent = exponentParts.count == 2 ? (Int(exponentParts[1]) ?? 0) : 0
        let components = mantissa.split(separator: ".", omittingEmptySubsequences: false)
        let whole = String(components[0])
        let fractional = components.count > 1 ? String(components[1]) : ""
        var decimalDigits = whole + fractional
        let decimalPosition = whole.count + exponent
        if decimalPosition <= 0 {
            decimalDigits = "0." + String(repeating: "0", count: -decimalPosition) + decimalDigits
        } else if decimalPosition >= decimalDigits.count {
            decimalDigits += String(repeating: "0", count: decimalPosition - decimalDigits.count)
        } else {
            decimalDigits.insert(".", at: decimalDigits.index(decimalDigits.startIndex, offsetBy: decimalPosition))
        }
        let normalized = decimalDigits.split(separator: ".", omittingEmptySubsequences: false)
        let integer = String(normalized[0])
        var fraction = normalized.count > 1 ? String(normalized[1]) : ""
        while fraction.count > digits && fraction.last == "0" { fraction.removeLast() }
        if fraction.count < digits { fraction += String(repeating: "0", count: digits - fraction.count) }
        return fraction.isEmpty ? integer : "\(integer).\(fraction)"
    }

    private func date(_ value: Date, dateOnly: Bool = false) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: isRTL ? "ar_QA" : "en_QA")
        formatter.calendar = Calendar(identifier: .gregorian)
        // Validity is a server date-only field, parsed at UTC midnight by the
        // adapter. Preserve that calendar day even outside Qatar's time zone.
        if dateOnly { formatter.timeZone = TimeZone(secondsFromGMT: 0) }
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: value)
    }
}
