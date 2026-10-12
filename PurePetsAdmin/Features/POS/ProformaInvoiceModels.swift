import Foundation

/// Wire v1 belongs to Infra's proformaInvoiceCommand. Money never passes through Double.
enum ProformaDecimal {
    static func parse(_ text: String, scale: Int, allowZero: Bool = true) -> Decimal? {
        let digits = Array("0123456789")
        let arabic = Array("٠١٢٣٤٥٦٧٨٩")
        let persian = Array("۰۱۲۳۴۵۶۷۸۹")
        var value = ""
        for character in text.trimmingCharacters(in: .whitespacesAndNewlines) {
            if let index = digits.firstIndex(of: character) ?? arabic.firstIndex(of: character) ?? persian.firstIndex(of: character) {
                value.append(digits[index])
            } else if character == "." || character == "٫" {
                value.append(".")
            } else { return nil }
        }
        let parts = value.split(separator: ".", omittingEmptySubsequences: false)
        guard !value.isEmpty, parts.count <= 2, !parts[0].isEmpty,
              parts[0].count <= 12,
              parts.count == 1 || (!parts[1].isEmpty && parts[1].count <= scale),
              let decimal = Decimal(string: value, locale: Locale(identifier: "en_US_POSIX")),
              !decimal.isNaN, decimal >= 0, allowZero || decimal > 0 else { return nil }
        return decimal
    }

    static func string(_ value: Decimal) -> String { NSDecimalNumber(decimal: value).stringValue }
    static func minor(_ value: Int) -> Decimal { Decimal(value) / 100 }
    static func rounded(_ value: Decimal, scale: Int = 2) -> Decimal {
        var original = value
        var result = Decimal()
        NSDecimalRound(&result, &original, scale, .plain)
        return result
    }
}

enum ProformaStatus: String, Sendable {
    case draft, issued, converted, cancelled
    var title: String { Language.get("Proforma_Status_" + rawValue, alter: nil) }
    var isEditable: Bool { self == .draft || self == .issued }
}

struct ProformaDiscount: Equatable, Sendable {
    var type = "none"
    var value = "0"
    var wire: [String: String] { ["type": type, "value": value] }
    func amount(on base: Decimal) throws -> Decimal {
        guard let decimal = ProformaDecimal.parse(value, scale: 2),
              ["none", "amount", "percent"].contains(type),
              type != "percent" || decimal <= 100,
              type != "none" || decimal == 0 else { throw ProformaFailure.invalidInput }
        let result: Decimal = type == "none" ? 0 : type == "percent"
            ? ProformaDecimal.rounded(base * decimal / 100) : decimal
        guard result <= base else { throw ProformaFailure.invalidInput }
        return result
    }
}

struct ProformaCustomer: Equatable, Sendable {
    let id: String
    let source: String
    let name: String
    let phone: String
    let email: String
    var wire: [String: String] { ["id": id, "source": source] }
    var pickerRecord: POSCustomerRecord {
        POSCustomerRecord(id: id, source: source, name: name, phone: phone, email: email)
    }
    init(_ record: POSCustomerRecord) {
        id = record.id; source = record.source; name = record.name
        phone = record.phone; email = record.email
    }
    init(wire: [String: Any]) throws {
        id = try ProformaWire.string(wire, "id")
        source = try ProformaWire.string(wire, "source")
        name = wire["name"] as? String ?? ""
        phone = wire["phone"] as? String ?? ""
        email = wire["email"] as? String ?? ""
    }
}

struct ProformaUnitPrice: Equatable, Sendable {
    let unitId: String
    var unitPrice: String
    var wire: [String: String] { ["unitId": unitId, "unitPrice": unitPrice] }
}

struct ProformaLine: Identifiable, Equatable, Sendable {
    var id: String
    let productId: String
    var name: String
    var sku: String
    var barcode: String
    var inventoryMode: String
    var quantityStep: String
    var unitsPerGroup: Int
    var groupName: String
    var quantityGroupId: String
    var quantity: String
    var unitPrice: String
    var unitIds: [String]
    var unitPrices: [ProformaUnitPrice]
    var discount: ProformaDiscount
    var taxRate: String
    var imageUrl: String? = nil
    var lineSubtotalMinor: Int = 0
    var lineDiscountMinor: Int = 0
    var globalDiscountMinor: Int = 0
    var taxMinor: Int = 0
    var totalMinor: Int = 0
    var requiresWholeQuantity: Bool { quantityStep == "1" || !unitIds.isEmpty || inventoryMode.uppercased().contains("INDIVIDUAL") || unitsPerGroup > 1 }

    var wire: [String: Any] {
        ["lineId": id, "productId": productId, "quantityGroupId": quantityGroupId,
         "quantity": quantity, "unitPrice": unitPrice, "unitIds": unitIds,
         "unitPrices": unitPrices.map(\.wire), "discount": discount.wire, "taxRate": taxRate]
    }

    init(catalog: ProformaCatalogItem) {
        id = UUID().uuidString; productId = catalog.productId; name = catalog.name
        sku = catalog.sku; barcode = catalog.barcode; inventoryMode = catalog.inventoryMode; quantityStep = catalog.quantityStep; unitsPerGroup = catalog.unitsPerGroup
        quantityGroupId = catalog.quantityGroupId; groupName = catalog.groupName; quantity = "1"; unitPrice = catalog.unitPrice
        unitIds = catalog.unitIds; unitPrices = catalog.unitPrices
        discount = ProformaDiscount(); taxRate = "0"
        imageUrl = catalog.imageUrl
    }
    init(wire: [String: Any]) throws {
        id = try ProformaWire.string(wire, "lineId")
        productId = try ProformaWire.string(wire, "productId")
        name = try ProformaWire.localizedName(wire)
        sku = wire["sku"] as? String ?? ""; barcode = wire["barcode"] as? String ?? ""
        inventoryMode = wire["inventoryMode"] as? String ?? ""
        quantityStep = wire["quantityStep"] as? String ?? ((wire["isLivePet"] as? Bool == true || wire["inventoryTrackingPolicy"] as? String == "lot") ? "1" : "0.001")
        unitsPerGroup = (wire["unitsPerGroup"] as? NSNumber)?.intValue ?? 1
        groupName = wire[Language.isRTL() ? "quantityGroupNameAr" : "quantityGroupNameEn"] as? String ?? ""
        quantityGroupId = try ProformaWire.string(wire, "quantityGroupId")
        quantity = try ProformaWire.decimalString(wire, "quantity", scale: 3)
        unitPrice = try ProformaWire.decimalString(wire, "unitPrice", scale: 2)
        unitIds = wire["unitIds"] as? [String] ?? []
        unitPrices = try (wire["unitPrices"] as? [[String: Any]] ?? []).map {
            ProformaUnitPrice(unitId: try ProformaWire.string($0, "unitId"), unitPrice: try ProformaWire.decimalString($0, "unitPrice", scale: 2))
        }
        let rawDiscount = wire["discount"] as? [String: Any] ?? [:]
        discount = ProformaDiscount(type: rawDiscount["type"] as? String ?? "none", value: rawDiscount["value"] as? String ?? "0")
        taxRate = try ProformaWire.decimalString(wire, "taxRate", scale: 2)
        if let direct = wire["imageUrl"] as? String ?? wire["imageURL"] as? String ?? wire["image"] as? String, !direct.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            imageUrl = direct.trimmingCharacters(in: .whitespacesAndNewlines)
        } else if let arr = wire["imageURLsArray"] as? [String], let first = arr.first(where: { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) {
            imageUrl = first.trimmingCharacters(in: .whitespacesAndNewlines)
        } else if let arr = wire["images"] as? [String], let first = arr.first(where: { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) {
            imageUrl = first.trimmingCharacters(in: .whitespacesAndNewlines)
        } else {
            imageUrl = nil
        }
        lineSubtotalMinor = try ProformaWire.integer(wire, "lineSubtotalMinor")
        lineDiscountMinor = try ProformaWire.integer(wire, "lineDiscountMinor")
        globalDiscountMinor = try ProformaWire.integer(wire, "globalDiscountMinor")
        taxMinor = try ProformaWire.integer(wire, "taxMinor")
        totalMinor = try ProformaWire.integer(wire, "totalMinor")
    }
}

struct ProformaCatalogItem: Identifiable, Sendable {
    let id: String
    let productId: String
    let name: String
    let sku: String
    let barcode: String
    let inventoryMode: String
    let quantityStep: String
    let unitsPerGroup: Int
    let quantityGroupId: String
    let groupName: String
    let unitPrice: String
    let currency: String
    let availableQuantity: String
    let unitIds: [String]
    let unitPrices: [ProformaUnitPrice]
    let imageUrl: String?
    let isLivePet: Bool
    init(wire: [String: Any]) throws {
        id = try ProformaWire.string(wire, "id"); productId = try ProformaWire.string(wire, "productId")
        name = try ProformaWire.localizedName(wire); sku = wire["sku"] as? String ?? ""
        barcode = wire["barcode"] as? String ?? ""; inventoryMode = wire["inventoryMode"] as? String ?? ""
        isLivePet = wire["isLivePet"] as? Bool ?? false
        quantityStep = wire["quantityStep"] as? String ?? ((isLivePet || wire["inventoryTrackingPolicy"] as? String == "lot") ? "1" : "0.001")
        unitsPerGroup = (wire["unitsPerGroup"] as? NSNumber)?.intValue ?? 1
        quantityGroupId = try ProformaWire.string(wire, "quantityGroupId")
        groupName = wire[Language.isRTL() ? "quantityGroupNameAr" : "quantityGroupNameEn"] as? String ?? ""
        unitPrice = try ProformaWire.decimalString(wire, "unitPrice", scale: 2)
        currency = try ProformaWire.string(wire, "currency")
        if let num = wire["availableQuantity"] as? NSNumber {
            availableQuantity = num.stringValue
        } else if let str = wire["availableQuantity"] as? String {
            availableQuantity = str
        } else {
            availableQuantity = "0"
        }
        unitIds = wire["unitIds"] as? [String] ?? []
        unitPrices = try (wire["unitPrices"] as? [[String: Any]] ?? []).map {
            ProformaUnitPrice(unitId: try ProformaWire.string($0, "unitId"), unitPrice: try ProformaWire.decimalString($0, "unitPrice", scale: 2))
        }
        if let direct = wire["imageUrl"] as? String ?? wire["imageURL"] as? String ?? wire["image"] as? String, !direct.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            imageUrl = direct.trimmingCharacters(in: .whitespacesAndNewlines)
        } else if let arr = wire["imageURLsArray"] as? [String], let first = arr.first(where: { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) {
            imageUrl = first.trimmingCharacters(in: .whitespacesAndNewlines)
        } else if let arr = wire["images"] as? [String], let first = arr.first(where: { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) {
            imageUrl = first.trimmingCharacters(in: .whitespacesAndNewlines)
        } else {
            imageUrl = nil
        }
    }
}

struct ProformaTotals: Equatable, Sendable {
    let subtotalMinor: Int
    let lineDiscountMinor: Int
    let discountMinor: Int
    let taxMinor: Int
    let totalMinor: Int
    init(subtotalMinor: Int, lineDiscountMinor: Int, discountMinor: Int, taxMinor: Int, totalMinor: Int) {
        self.subtotalMinor = subtotalMinor; self.discountMinor = discountMinor
        self.lineDiscountMinor = lineDiscountMinor
        self.taxMinor = taxMinor; self.totalMinor = totalMinor
    }
    init(wire: [String: Any]) throws {
        subtotalMinor = try ProformaWire.integer(wire, "subtotalMinor")
        lineDiscountMinor = try ProformaWire.integer(wire, "lineDiscountMinor")
        discountMinor = try ProformaWire.integer(wire, "discountMinor")
        taxMinor = try ProformaWire.integer(wire, "taxMinor")
        totalMinor = try ProformaWire.integer(wire, "totalMinor")
    }
}

/// Formats any proforma number into a clean, unified presentation string (e.g. PF-261011-D0AF17).
/// Gracefully handles legacy 52-character hashes, 8-digit years, and truncates long identifiers
/// so they fit single-line headers, navigation bars, and PDF print headers.
public func proformaDisplayNumber(_ number: String) -> String {
    let clean = number.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !clean.isEmpty else { return clean }
    let parts = clean.split(separator: "-")
    if parts.count >= 3, parts[0] == "PF" {
        var dateStr = String(parts[1])
        if dateStr.count == 8 {
            dateStr = String(dateStr.dropFirst(2))
        }
        let hexPart = parts[2]
        let shortHex = String(hexPart.prefix(6)).uppercased()
        return "PF-\(dateStr)-\(shortHex)"
    }
    if clean.count > 18 {
        if clean.hasPrefix("PF-") {
            return "\(clean.prefix(11))…\(clean.suffix(4))"
        }
        return String(clean.prefix(16))
    }
    return clean
}

struct ProformaInvoice: Identifiable, Hashable, Equatable, Sendable {
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
        hasher.combine(version)
    }

    static func == (lhs: ProformaInvoice, rhs: ProformaInvoice) -> Bool {
        lhs.id == rhs.id && lhs.version == rhs.version && lhs.status == rhs.status && lhs.updatedAt == rhs.updatedAt
    }

    let id: String
    let number: String
    var displayNumber: String { proformaDisplayNumber(number) }
    let version: Int
    let branchId: String
    let branchName: String
    let status: ProformaStatus
    let isExpired: Bool
    let customer: ProformaCustomer?
    let items: [ProformaLine]
    let discount: ProformaDiscount
    let currency: String
    let validUntil: String?
    let notes: String
    let totals: ProformaTotals
    let createdAt: Date
    let updatedAt: Date
    let issuedAt: Date?
    let convertedTransactionId: String?
    init(wire: [String: Any]) throws {
        id = try ProformaWire.string(wire, "id"); number = try ProformaWire.string(wire, "number")
        version = try ProformaWire.integer(wire, "version", positive: true)
        branchId = try ProformaWire.string(wire, "branchId")
        branchName = wire[Language.isRTL() ? "branchNameAr" : "branchNameEn"] as? String ?? wire["branchName"] as? String ?? ""
        guard let parsed = ProformaStatus(rawValue: try ProformaWire.string(wire, "status")) else { throw ProformaFailure.invalidResponse }
        status = parsed; isExpired = wire["isExpired"] as? Bool ?? false
        customer = try (wire["customer"] as? [String: Any]).map(ProformaCustomer.init(wire:))
        guard let lines = wire["items"] as? [[String: Any]], let rawTotals = wire["totals"] as? [String: Any] else { throw ProformaFailure.invalidResponse }
        items = try lines.map(ProformaLine.init(wire:))
        let rawDiscount = wire["discount"] as? [String: Any] ?? [:]
        discount = ProformaDiscount(type: rawDiscount["type"] as? String ?? "none", value: rawDiscount["value"] as? String ?? "0")
        currency = try ProformaWire.string(wire, "currency"); validUntil = wire["validUntil"] as? String
        notes = wire["notes"] as? String ?? ""; totals = try ProformaTotals(wire: rawTotals)
        guard let created = ProformaWire.date(wire["createdAt"]), let updated = ProformaWire.date(wire["updatedAt"]) else { throw ProformaFailure.invalidResponse }
        createdAt = created; updatedAt = updated; issuedAt = ProformaWire.date(wire["issuedAt"])
        convertedTransactionId = wire["convertedTransactionId"] as? String
    }
}

struct ProformaDraft: Equatable, Sendable {
    let localID: String
    var invoiceID: String?
    var version: Int?
    var number: String?
    var displayNumber: String? { number.map { proformaDisplayNumber($0) } }
    var branchId: String
    var currency: String
    var customer: ProformaCustomer?
    var items: [ProformaLine]
    var discount: ProformaDiscount
    var validUntil: String?
    var notes: String
    init(branchId: String, currency: String) {
        localID = UUID().uuidString; self.branchId = branchId; self.currency = currency
        customer = nil; items = []; discount = ProformaDiscount(); validUntil = nil; notes = ""
    }
    init(_ invoice: ProformaInvoice) {
        localID = invoice.id; invoiceID = invoice.id; version = invoice.version; number = invoice.number
        branchId = invoice.branchId; currency = invoice.currency; customer = invoice.customer
        items = invoice.items; discount = invoice.discount; validUntil = invoice.validUntil; notes = invoice.notes
    }
    func payload() throws -> [String: Any] {
        guard items.count <= 50, notes.count <= 2000,
              Set(items.map(\.productId)).count == items.count,
              items.flatMap(\.unitIds).count <= 50 else { throw ProformaFailure.invalidInput }
        var normalized = items
        for index in normalized.indices {
            guard let quantity = ProformaDecimal.parse(normalized[index].quantity, scale: 3, allowZero: false), quantity >= Decimal(string: "0.001")!, quantity <= 100000,
                  let price = ProformaDecimal.parse(normalized[index].unitPrice, scale: 2), price <= Decimal(string: "999999999.99")!,
                  let rate = ProformaDecimal.parse(normalized[index].taxRate, scale: 2), rate <= 100,
                  !normalized[index].requiresWholeQuantity || quantity == ProformaDecimal.rounded(quantity, scale: 0),
                  normalized[index].unitIds.isEmpty || quantity == Decimal(normalized[index].unitIds.count) else { throw ProformaFailure.invalidInput }
            normalized[index].quantity = ProformaDecimal.string(quantity)
            normalized[index].unitPrice = ProformaDecimal.string(price)
            normalized[index].taxRate = ProformaDecimal.string(rate)
            let gross = normalized[index].unitPrices.isEmpty ? ProformaDecimal.rounded(price * quantity) : normalized[index].unitPrices.reduce(Decimal(0)) { $0 + (ProformaDecimal.parse($1.unitPrice, scale: 2) ?? 0) }
            _ = try normalized[index].discount.amount(on: gross)
            normalized[index].discount.value = ProformaDecimal.string(ProformaDecimal.parse(normalized[index].discount.value, scale: 2)!)
        }
        _ = try estimatedTotals()
        var normalizedDiscount = discount
        guard let discountValue = ProformaDecimal.parse(discount.value, scale: 2) else { throw ProformaFailure.invalidInput }
        normalizedDiscount.value = ProformaDecimal.string(discountValue)
        return ["customer": customer?.wire as Any? ?? NSNull(), "items": normalized.map(\.wire),
                "discount": normalizedDiscount.wire, "currency": currency, "validUntil": validUntil as Any? ?? NSNull(), "notes": notes]
    }

    /// Local estimates mirror Infra cent rounding/allocation; only server totals are exported or converted.
    func estimatedTotals() throws -> ProformaTotals {
        func cents(_ amount: Decimal) -> Int { NSDecimalNumber(decimal: ProformaDecimal.rounded(amount) * 100).intValue }
        var gross: [Int] = []; var lineDiscounts: [Int] = []; var taxRates: [Decimal] = []
        for line in items {
            guard let quantity = ProformaDecimal.parse(line.quantity, scale: 3, allowZero: false), quantity >= Decimal(string: "0.001")!, quantity <= 100000,
                  let price = ProformaDecimal.parse(line.unitPrice, scale: 2), price <= Decimal(string: "999999999.99")!,
                  let rate = ProformaDecimal.parse(line.taxRate, scale: 2), rate <= 100,
                  !line.requiresWholeQuantity || quantity == ProformaDecimal.rounded(quantity, scale: 0),
                  line.unitIds.isEmpty || quantity == Decimal(line.unitIds.count) else { throw ProformaFailure.invalidInput }
            let amount = line.unitPrices.isEmpty ? price * quantity : try line.unitPrices.reduce(Decimal(0)) { amount, unit in
                guard let unitPrice = ProformaDecimal.parse(unit.unitPrice, scale: 2) else { throw ProformaFailure.invalidInput }
                return amount + unitPrice
            }
            let roundedGross = ProformaDecimal.rounded(amount)
            guard roundedGross <= Decimal(string: "999999999.99")! else { throw ProformaFailure.invalidInput }
            gross.append(cents(roundedGross)); lineDiscounts.append(cents(try line.discount.amount(on: roundedGross))); taxRates.append(rate)
        }
        let subtotal = gross.reduce(0, +)
        let net = zip(gross, lineDiscounts).map { $0 - $1 }
        let netSum = net.reduce(0, +)
        let global = cents(try discount.amount(on: ProformaDecimal.minor(netSum)))
        var shares = Array(repeating: 0, count: net.count)
        if netSum > 0 && global > 0 {
            var remainders: [(Int, Decimal)] = []
            for index in net.indices {
                let ideal = Decimal(net[index]) * Decimal(global) / Decimal(netSum)
                var input = ideal; var floor = Decimal(); NSDecimalRound(&floor, &input, 0, .down)
                shares[index] = NSDecimalNumber(decimal: floor).intValue
                remainders.append((index, ideal - floor))
            }
            remainders.sort { $0.1 == $1.1 ? $0.0 < $1.0 : $0.1 > $1.1 }
            let deficit = global - shares.reduce(0, +)
            if !remainders.isEmpty && deficit > 0 {
                for index in 0..<deficit {
                    shares[remainders[index % remainders.count].0] += 1
                }
            }
        }
        let tax = net.indices.reduce(0) { $0 + cents(ProformaDecimal.minor(net[$1] - shares[$1]) * taxRates[$1] / 100) }
        let total = netSum - global + tax
        guard subtotal <= 99_999_999_999, total <= 99_999_999_999 else { throw ProformaFailure.invalidInput }
        return ProformaTotals(subtotalMinor: subtotal, lineDiscountMinor: lineDiscounts.reduce(0, +), discountMinor: global, taxMinor: tax, totalMinor: total)
    }
}

enum ProformaFailure: Error, LocalizedError, Equatable {
    case invalidInput, invalidResponse, denied, unauthenticated, conflict, unavailable, stockOrPricing, expired
    var errorDescription: String? {
        let key: String
        switch self {
        case .invalidInput: key = "InvalidInput"
        case .invalidResponse: key = "InvalidResponse"
        case .denied: key = "Denied"
        case .unauthenticated: key = "Unauthenticated"
        case .conflict: key = "Conflict"
        case .unavailable: key = "Unavailable"
        case .stockOrPricing: key = "StockOrPricing"
        case .expired: key = "Expired"
        }
        return Language.get("Proforma_Error_" + key, alter: nil)
    }
}

enum ProformaWire {
    static func localizedName(_ wire: [String: Any]) throws -> String {
        let selected = (wire[Language.isRTL() ? "nameAr" : "nameEn"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if !selected.isEmpty { return selected }
        let fallback = (wire["name"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return fallback.isEmpty ? Language.get("Proforma_UnnamedProduct", alter: nil) : fallback
    }
    static func string(_ wire: [String: Any], _ key: String) throws -> String {
        guard let value = wire[key] as? String, !value.isEmpty else { throw ProformaFailure.invalidResponse }
        return value
    }
    static func decimalString(_ wire: [String: Any], _ key: String, scale: Int) throws -> String {
        let value = try string(wire, key)
        guard ProformaDecimal.parse(value, scale: scale) != nil else { throw ProformaFailure.invalidResponse }
        return value
    }
    static func integer(_ wire: [String: Any], _ key: String, positive: Bool = false) throws -> Int {
        guard let number = wire[key] as? NSNumber, String(cString: number.objCType) != "c",
              let integer = Int(number.stringValue), integer >= (positive ? 1 : 0) else { throw ProformaFailure.invalidResponse }
        return integer
    }
    static func date(_ value: Any?) -> Date? {
        guard let value = value as? String else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: value) ?? ISO8601DateFormatter().date(from: value)
    }
    static func validityDate(_ text: String?) -> Date? {
        guard let text else { return nil }
        let formatter = DateFormatter(); formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX"); formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"; formatter.isLenient = false
        return formatter.date(from: text)
    }
    static func validityString(_ date: Date) -> String {
        let formatter = DateFormatter(); formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX"); formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"; return formatter.string(from: date)
    }
}
