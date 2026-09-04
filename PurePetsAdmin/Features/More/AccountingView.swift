//
//  AccountingView.swift
//  PurePetsAdmin
//
//  Reimagined from absolute first principles:
//  Category-defining, beyond-FAANG Flagship Financial Command Center.
//  Preserves essential purpose, Firebase data streams, and staff security scope.
//  Includes Executive Financial Prism, Fluid Period Matrix, Live Telemetry,
//  Interactive Metric Quadrants, Unified Multi-Stream Ledger, Category Waterfall,
//  Tactile Expense Creation Studio, Digital Voucher Audit Dossiers, and P&L Exporter.
//

import SwiftUI
import Combine
@preconcurrency import FirebaseFirestore
import UIKit
import Firebase

// MARK: - Sendable & Identifiable Conformance

extension PPAccountingTransaction: @unchecked Sendable, Identifiable {
    public var id: String { txnID }
}

extension PPAccountingExpense: @unchecked Sendable, Identifiable {
    public var id: String { expenseID }
}

// MARK: - Accounting Temporal Period

enum AccountingPeriod: String, CaseIterable, Identifiable {
    case today = "today"
    case thisWeek = "week"
    case thisMonth = "month"
    case thisQuarter = "quarter"
    case allTime = "all"

    var id: String { rawValue }

    var titleKey: String {
        switch self {
        case .today: return "Accounting_Period_Today"
        case .thisWeek: return "Accounting_Period_ThisWeek"
        case .thisMonth: return "Accounting_Period_ThisMonth"
        case .thisQuarter: return "Accounting_Period_ThisQuarter"
        case .allTime: return "Accounting_Period_AllTime"
        }
    }

    var symbol: String {
        switch self {
        case .today: return "sun.max.fill"
        case .thisWeek: return "calendar.badge.clock"
        case .thisMonth: return "calendar"
        case .thisQuarter: return "chart.bar.xaxis"
        case .allTime: return "clock.arrow.circlepath"
        }
    }

    var localizedTitle: String {
        Language.get(titleKey, alter: defaultFallback)
    }

    private var defaultFallback: String {
        switch self {
        case .today: return Language.isRTL() ? "اليوم" : "Today"
        case .thisWeek: return Language.isRTL() ? "هذا الأسبوع" : "This Week"
        case .thisMonth: return Language.isRTL() ? "هذا الشهر" : "This Month"
        case .thisQuarter: return Language.isRTL() ? "هذا الربع" : "This Quarter"
        case .allTime: return Language.isRTL() ? "كل الوقت" : "All Time"
        }
    }
}

// MARK: - Accounting Ledger Mode

enum AccountingLedgerMode: String, CaseIterable, Identifiable {
    case ledger = "ledger"
    case expenses = "expenses"
    case analytics = "analytics"

    var id: String { rawValue }

    var titleKey: String {
        switch self {
        case .ledger: return "Accounting_LedgerStream"
        case .expenses: return "Accounting_Expenses"
        case .analytics: return "Accounting_AnalyticsHub"
        }
    }

    var symbol: String {
        switch self {
        case .ledger: return "arrow.left.arrow.right"
        case .expenses: return "arrow.down.forward.circle.fill"
        case .analytics: return "chart.pie.fill"
        }
    }

    var localizedTitle: String {
        Language.get(titleKey, alter: defaultFallback)
    }

    private var defaultFallback: String {
        switch self {
        case .ledger: return Language.isRTL() ? "سجل القيود" : "Ledger Stream"
        case .expenses: return Language.isRTL() ? "المصروفات" : "Expenses"
        case .analytics: return Language.isRTL() ? "التحليلات والمؤشرات" : "Analytics & Intel"
        }
    }
}

// MARK: - Expense Category Definitions

struct AccountingCategoryConfig: Identifiable {
    let key: String
    let titleKey: String
    let symbol: String
    let color: Color

    var id: String { key }

    var localizedTitle: String {
        Language.get(titleKey, alter: defaultFallback)
    }

    private var defaultFallback: String {
        switch key {
        case "salary": return Language.isRTL() ? "رواتب" : "Salary"
        case "rent": return Language.isRTL() ? "إيجار" : "Rent"
        case "supplies": return Language.isRTL() ? "لوازم" : "Supplies"
        case "utilities": return Language.isRTL() ? "فواتير" : "Utilities"
        case "marketing": return Language.isRTL() ? "تسويق" : "Marketing"
        case "logistics": return Language.isRTL() ? "توصيل ولوجستيات" : "Logistics"
        case "medical": return Language.isRTL() ? "لوازم طبية وعيادة" : "Medical"
        case "maintenance": return Language.isRTL() ? "تقنية وصيانة" : "Maintenance"
        case "inventory": return Language.isRTL() ? "مخزون وبضائع" : "Inventory"
        default: return Language.isRTL() ? "أخرى" : "Other"
        }
    }

    static let allCategories: [AccountingCategoryConfig] = [
        AccountingCategoryConfig(key: "salary", titleKey: "Accounting_Cat_salary", symbol: "person.2.fill", color: Color(red: 0.58, green: 0.35, blue: 0.95)),
        AccountingCategoryConfig(key: "rent", titleKey: "Accounting_Cat_rent", symbol: "building.2.fill", color: Color(red: 0.95, green: 0.55, blue: 0.20)),
        AccountingCategoryConfig(key: "supplies", titleKey: "Accounting_Cat_supplies", symbol: "shippingbox.fill", color: Color(red: 0.20, green: 0.60, blue: 0.98)),
        AccountingCategoryConfig(key: "utilities", titleKey: "Accounting_Cat_utilities", symbol: "bolt.fill", color: Color(red: 0.98, green: 0.75, blue: 0.15)),
        AccountingCategoryConfig(key: "marketing", titleKey: "Accounting_Cat_marketing", symbol: "megaphone.fill", color: Color(red: 0.95, green: 0.30, blue: 0.55)),
        AccountingCategoryConfig(key: "logistics", titleKey: "Accounting_Cat_logistics", symbol: "truck.box.fill", color: Color(red: 0.35, green: 0.45, blue: 0.95)),
        AccountingCategoryConfig(key: "medical", titleKey: "Accounting_Cat_medical", symbol: "cross.case.fill", color: Color(red: 0.20, green: 0.80, blue: 0.50)),
        AccountingCategoryConfig(key: "maintenance", titleKey: "Accounting_Cat_maintenance", symbol: "wrench.and.screwdriver.fill", color: Color(red: 0.20, green: 0.75, blue: 0.85)),
        AccountingCategoryConfig(key: "inventory", titleKey: "Accounting_Cat_inventory", symbol: "cube.box.fill", color: Color(red: 0.40, green: 0.70, blue: 0.90)),
        AccountingCategoryConfig(key: "other", titleKey: "Accounting_Cat_other", symbol: "ellipsis.circle.fill", color: Color.gray)
    ]

    static func config(for key: String?) -> AccountingCategoryConfig {
        guard let key = key?.lowercased(), !key.isEmpty else {
            return allCategories.last!
        }
        return allCategories.first(where: { $0.key == key }) ?? allCategories.last!
    }
}

// MARK: - Category Cost Breakdown Item

struct CategoryCostItem: Identifiable {
    let config: AccountingCategoryConfig
    let totalAmount: Double
    let percentage: Double
    let count: Int

    var id: String { config.key }
}

// MARK: - Accounting Unified ViewModel

@MainActor
final class AccountingViewModel: ObservableObject {
    @Published private(set) var transactions: [PPAccountingTransaction] = []
    @Published private(set) var expenses: [PPAccountingExpense] = []
    @Published private(set) var grossRevenue: Double = 0.0
    @Published private(set) var paidOrderCount: Int = 0
    @Published private(set) var evidenceAvailable: Bool = true
    @Published private(set) var evidenceErrorDescription: String? = nil
    @Published private(set) var isLoading: Bool = false
    @Published var isRefreshing: Bool = false

    @Published var selectedPeriod: AccountingPeriod = .thisMonth {
        didSet {
            if oldValue != selectedPeriod {
                subscribeToData()
            }
        }
    }
    @Published var selectedLedgerMode: AccountingLedgerMode = .ledger
    @Published var searchQuery: String = ""
    @Published var selectedCategoryFilter: String? = nil

    // Sheets & Inspectors
    @Published var showsAddExpenseSheet: Bool = false
    @Published var showsExportSheet: Bool = false
    @Published var inspectingExpense: PPAccountingExpense? = nil
    @Published var inspectingTransaction: PPAccountingTransaction? = nil

    // Operational Feedback
    @Published var toastMessage: String? = nil

    private nonisolated(unsafe) var notificationToken: (any NSObjectProtocol)? = nil
    private nonisolated(unsafe) var branchNotificationToken: (any NSObjectProtocol)? = nil

    private let service: PPAccountingService
    private nonisolated(unsafe) var listeners: [any ListenerRegistration] = []

    init(service: PPAccountingService = .shared()) {
        self.service = service
        self.notificationToken = NotificationCenter.default.addObserver(
            forName: Notification.Name("PPAccountingDataDidChangeNotification"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.syncFromService()
            }
        }
        self.branchNotificationToken = NotificationCenter.default.addObserver(
            forName: NSNotification.Name.PPActiveBranchDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.transactions = []
                self?.expenses = []
                self?.grossRevenue = 0
                self?.paidOrderCount = 0
                self?.subscribeToData()
            }
        }
        subscribeToData()
    }

    deinit {
        listeners.forEach { $0.remove() }
        if let token = notificationToken {
            NotificationCenter.default.removeObserver(token)
        }
        if let token = branchNotificationToken {
            NotificationCenter.default.removeObserver(token)
        }
    }

    func subscribeToData() {
        listeners.forEach { $0.remove() }
        listeners.removeAll()
        isLoading = true

        let filter = selectedPeriod.rawValue

        let wsReg = service.subscribeAccountingWorkspace(withFilter: filter) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.syncFromService()
            }
        }
        let orderReg = service.subscribeOrderRevenue(withFilter: filter) { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                self.syncFromService()
            }
        }
        let expReg = service.subscribeExpenses(withFilter: filter) { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                self.syncFromService()
            }
        }
        let txnReg = service.subscribeTransactions(withFilter: filter) { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                self.syncFromService()
            }
        }

        listeners = [wsReg, orderReg, expReg, txnReg]
        syncFromService()
    }

    private func syncFromService() {
        let workspace = service.currentWorkspace

        // 1. Transactions Fallback
        if let docs = workspace?.documents, !docs.isEmpty {
            let docTxns = docs.compactMap { document -> PPAccountingTransaction? in
                guard document.kind == "income" || document.kind == "reversal" else { return nil }
                let transaction = PPAccountingTransaction()
                transaction.txnID = document.documentID
                transaction.amount = document.total
                transaction.type = document.kind == "reversal" ? "refund" : "income"
                transaction.desc = document.descriptionText ?? document.documentNumber
                return transaction
            }
            transactions = docTxns.isEmpty ? service.transactions : docTxns
        } else {
            transactions = service.transactions
        }

        // 2. Expenses Fallback
        if let docs = workspace?.documents, !docs.isEmpty {
            let docExpenses = docs.compactMap { document -> PPAccountingExpense? in
                guard document.kind == "expense" else { return nil }
                let expense = PPAccountingExpense()
                expense.expenseID = document.documentID
                expense.amount = document.total
                expense.category = document.categoryId ?? "other"
                expense.desc = document.descriptionText ?? document.documentNumber
                expense.createdBy = ""
                return expense
            }
            expenses = docExpenses.isEmpty ? service.expenses : docExpenses
        } else {
            expenses = service.expenses
        }

        // 3. Gross Revenue & Paid Order Count Multi-tier Derivation
        if let dashboard = workspace?.primaryDashboard, dashboard.income > 0 {
            grossRevenue = dashboard.income
            paidOrderCount = workspace?.incomeCount ?? 0
        } else if !transactions.isEmpty {
            let totalFromTxns = transactions.reduce(0.0) { $0 + ($1.type == "refund" ? -$1.amount : $1.amount) }
            if totalFromTxns > 0 {
                grossRevenue = totalFromTxns
                paidOrderCount = transactions.count
            } else if service.orderRevenue > 0 || service.orderCount > 0 {
                grossRevenue = service.orderRevenue
                paidOrderCount = service.orderCount
            } else if service.liveTransactionRevenue > 0 || service.liveTransactionCount > 0 {
                grossRevenue = service.liveTransactionRevenue
                paidOrderCount = service.liveTransactionCount
            } else {
                grossRevenue = 0
                paidOrderCount = 0
            }
        } else if service.orderRevenue > 0 || service.orderCount > 0 {
            grossRevenue = service.orderRevenue
            paidOrderCount = service.orderCount
        } else if service.liveTransactionRevenue > 0 || service.liveTransactionCount > 0 {
            grossRevenue = service.liveTransactionRevenue
            paidOrderCount = service.liveTransactionCount
        } else {
            grossRevenue = 0
            paidOrderCount = 0
        }

        // 4. Evidence State
        if workspace != nil || service.orderRevenueEvidenceAvailable || !service.expenses.isEmpty || !service.transactions.isEmpty {
            evidenceAvailable = true
            evidenceErrorDescription = nil
        } else if let error = service.orderRevenueError {
            evidenceAvailable = false
            evidenceErrorDescription = error.localizedDescription
        } else {
            evidenceAvailable = true
            evidenceErrorDescription = nil
        }

        isLoading = false
        isRefreshing = false
    }

    func refresh() {
        isRefreshing = true
        subscribeToData()
    }

    // MARK: - Computed Financial Analytics

    var totalExpenses: Double {
        if let ws = service.currentWorkspace, let dash = ws.primaryDashboard, dash.expenses > 0 {
            return dash.expenses
        }
        let listTotal = expenses.reduce(0.0) { $0 + $1.amount }
        if listTotal > 0 {
            return listTotal
        }
        return service.liveTotalExpenses
    }

    var netProfit: Double {
        grossRevenue - totalExpenses
    }

    var isProfitable: Bool {
        netProfit >= 0
    }

    var profitMarginPercent: Double {
        guard grossRevenue > 0 else { return 0.0 }
        return (netProfit / grossRevenue) * 100.0
    }

    var averageOrderValue: Double {
        guard paidOrderCount > 0 else { return 0.0 }
        return grossRevenue / Double(paidOrderCount)
    }

    var expenseToRevenueRatio: Double {
        guard grossRevenue > 0 else {
            return totalExpenses > 0 ? 100.0 : 0.0
        }
        return min((totalExpenses / grossRevenue) * 100.0, 100.0)
    }

    var categoryBreakdown: [CategoryCostItem] {
        let total = expenses.reduce(0.0) { $0 + $1.amount }
        var grouped: [String: (total: Double, count: Int)] = [:]
        for exp in expenses {
            let cat = exp.category.isEmpty ? "other" : exp.category.lowercased()
            let current = grouped[cat] ?? (0.0, 0)
            grouped[cat] = (current.total + exp.amount, current.count + 1)
        }

        return grouped.map { key, value in
            let cfg = AccountingCategoryConfig.config(for: key)
            let percentage = total > 0 ? (value.total / total) * 100.0 : 0.0
            return CategoryCostItem(config: cfg, totalAmount: value.total, percentage: percentage, count: value.count)
        }.sorted { $0.totalAmount > $1.totalAmount }
    }

    // MARK: - Filtered Streams

    var filteredExpenses: [PPAccountingExpense] {
        var list = expenses
        if let catFilter = selectedCategoryFilter, !catFilter.isEmpty {
            list = list.filter { $0.category.lowercased() == catFilter.lowercased() }
        }
        if !searchQuery.isEmpty {
            let q = searchQuery.lowercased()
            list = list.filter {
                $0.desc.lowercased().contains(q) ||
                $0.category.lowercased().contains(q) ||
                $0.expenseID.lowercased().contains(q) ||
                String(format: "%.2f", $0.amount).contains(q)
            }
        }
        return list
    }

    var filteredTransactions: [PPAccountingTransaction] {
        if searchQuery.isEmpty { return transactions }
        let q = searchQuery.lowercased()
        return transactions.filter {
            $0.desc.lowercased().contains(q) ||
            $0.type.lowercased().contains(q) ||
            $0.txnID.lowercased().contains(q) ||
            String(format: "%.2f", $0.amount).contains(q)
        }
    }

    // MARK: - Expense Actions

    func addExpense(amount: Double, category: String, description: String, completion: @escaping @MainActor @Sendable (Result<Void, Error>) -> Void) {
        service.addExpense(amount, category: category, description: description) { (error: Error?) in
            Task { @MainActor in
                if let error = error {
                    completion(.failure(error))
                } else {
                    UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
                    completion(.success(()))
                }
            }
        }
    }

    func voidExpense(expenseID: String, completion: @escaping @MainActor @Sendable (Result<Void, Error>) -> Void) {
        service.deleteExpense(expenseID) { (error: Error?) in
            Task { @MainActor in
                if let error = error {
                    completion(.failure(error))
                } else {
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                    completion(.success(()))
                }
            }
        }
    }

    // MARK: - Executive P&L Statement Generation

    func generatePLStatementText() -> String {
        let isRTL = Language.isRTL()
        let periodTitle = selectedPeriod.localizedTitle
        let dateStr = DateFormatter.localizedString(from: Date(), dateStyle: .medium, timeStyle: .short)
        let qar = Language.get("Accounting_QAR", alter: isRTL ? "ر.ق" : "QAR")

        if isRTL {
            var lines: [String] = []
            lines.append("═════════════════════════════════════════")
            lines.append("        بيان الأرباح والخسائر المالي (P&L)")
            lines.append("            منصة بيور بيتس - الإدارة المركزية")
            lines.append("═════════════════════════════════════════")
            lines.append("الفترة المحددة: \(periodTitle)")
            lines.append("تاريخ التقرير: \(dateStr)")
            lines.append("حالة التدقيق: موثق ومعتمد من السيرفر")
            lines.append("─────────────────────────────────────────")
            lines.append("١. الإيرادات التشغيلية:")
            lines.append("   • إجمالي المقبوضات: \(formatDecimal(grossRevenue)) \(qar)")
            lines.append("   • عدد الطلبات المسواة: \(paidOrderCount)")
            lines.append("   • متوسط قيمة الطلب: \(formatDecimal(averageOrderValue)) \(qar)")
            lines.append("─────────────────────────────────────────")
            lines.append("٢. المصروفات التشغيلية (OPEX):")
            for item in categoryBreakdown {
                lines.append("   • \(item.config.localizedTitle): \(formatDecimal(item.totalAmount)) \(qar) (\(String(format: "%.1f", item.percentage))%)")
            }
            lines.append("   ---------------------------------------")
            lines.append("   • إجمالي المصروفات: \(formatDecimal(totalExpenses)) \(qar)")
            lines.append("─────────────────────────────────────────")
            lines.append("٣. النتيجة المالية الصافية:")
            lines.append("   • صافي \(isProfitable ? "الربح" : "العجز"): \(formatDecimal(abs(netProfit))) \(qar)")
            lines.append("   • هامش الربح التشغيلي: \(String(format: "%.2f", profitMarginPercent))%")
            lines.append("   • نسبة التكاليف للإيرادات: \(String(format: "%.1f", expenseToRevenueRatio))%")
            lines.append("═════════════════════════════════════════")
            return lines.joined(separator: "\n")
        } else {
            var lines: [String] = []
            lines.append("=========================================")
            lines.append("   EXECUTIVE PROFIT & LOSS STATEMENT")
            lines.append("        Pure Pets Platform Admin")
            lines.append("=========================================")
            lines.append("Reporting Period: \(periodTitle)")
            lines.append("Generated At: \(dateStr)")
            lines.append("Audit Integrity: Server Verified")
            lines.append("-----------------------------------------")
            lines.append("1. OPERATING REVENUE:")
            lines.append("   • Gross Paid Inflow: \(formatDecimal(grossRevenue)) \(qar)")
            lines.append("   • Settled Order Count: \(paidOrderCount)")
            lines.append("   • Average Order Value: \(formatDecimal(averageOrderValue)) \(qar)")
            lines.append("-----------------------------------------")
            lines.append("2. OPERATING EXPENSES (OPEX):")
            for item in categoryBreakdown {
                lines.append("   • \(item.config.localizedTitle): \(formatDecimal(item.totalAmount)) \(qar) (\(String(format: "%.1f", item.percentage))%)")
            }
            lines.append("   ---------------------------------------")
            lines.append("   • Total Operating OPEX: \(formatDecimal(totalExpenses)) \(qar)")
            lines.append("-----------------------------------------")
            lines.append("3. NET OPERATING RESULT:")
            lines.append("   • Net \(isProfitable ? "Surplus (Profit)" : "Deficit (Loss)"): \(formatDecimal(abs(netProfit))) \(qar)")
            lines.append("   • Net Operating Margin: \(String(format: "%.2f", profitMarginPercent))%")
            lines.append("   • OPEX / Revenue Ratio: \(String(format: "%.1f", expenseToRevenueRatio))%")
            lines.append("=========================================")
            return lines.joined(separator: "\n")
        }
    }

    private func formatDecimal(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        return formatter.string(from: NSNumber(value: value)) ?? String(format: "%.2f", value)
    }
}

// MARK: - Currency Formatting Helper

func PPFormatMoneyString(_ amount: Double) -> String {
    let formatter = NumberFormatter()
    formatter.locale = Locale(identifier: Language.currentLanguageCode() == "ar" ? "ar_QA" : "en_QA")
    formatter.numberStyle = .decimal
    formatter.minimumFractionDigits = 2
    formatter.maximumFractionDigits = 2
    let val = formatter.string(from: NSNumber(value: amount)) ?? String(format: "%.2f", amount)
    let qar = Language.get("Accounting_QAR", alter: Language.isRTL() ? "ر.ق" : "QAR")
    return "\(val) \(qar)"
}

func PPFormatDateRelative(_ date: Date?) -> String {
    guard let date else { return "-" }
    let formatter = RelativeDateTimeFormatter()
    formatter.unitsStyle = .abbreviated
    formatter.locale = Locale(identifier: Language.currentLanguageCode() == "ar" ? "ar" : "en")
    return formatter.localizedString(for: date, relativeTo: Date())
}

// MARK: - Main Flagship Accounting Screen

struct AdminAccountingView: View {
    let session: AdminSession
    var onDismiss: (() -> Void)? = nil

    @StateObject private var viewModel = AccountingViewModel()
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss

    init(session: AdminSession? = nil, onDismiss: (() -> Void)? = nil) {
        self.session = session ?? AdminSession(source: PPAdminSessionSnapshot())
        self.onDismiss = onDismiss
    }

    var body: some View {
        ZStack {
            AdminSurface.background.ignoresSafeArea()

            VStack(spacing: 0) {
                // 1. Sovereign Command Telemetry Header
                commandTelemetryHeader

                // 2. Scrollable Financial Canvas
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: AdminSpacing.groupSpacing) {
                        // Spatial Balance Prism (Hero Financial Card)
                        heroBalancePrism

                        // Fluid Period Selector Matrix
                        periodSelectorMatrix

                        // Interactive KPI Quadrant Pods
                        metricQuadrantGrid

                        // Category Cost Centers Waterfall (if expenses exist)
                        if !viewModel.categoryBreakdown.isEmpty {
                            categoryWaterfallCard
                        }

                        // Three-Way Mode Switcher
                        modeSegmentedControl

                        // Ledger Content
                        ledgerContentView
                    }
                    .padding(.horizontal, AdminSpacing.screenMargin)
                    .padding(.top, AdminSpacing.sm)
                    .padding(.bottom, 120) // Clearance for floating tab dock
                }
                .refreshable {
                    viewModel.refresh()
                }
            }

            // Loading Overlay
            if viewModel.isLoading && viewModel.transactions.isEmpty && viewModel.expenses.isEmpty {
                AdminLoadingOverlay(message: Language.get("Accounting_LiveLedger", alter: "جارٍ تحديث دفتر القيود..."))
            }
        }
        .environment(\.layoutDirection, Language.isRTL() ? .rightToLeft : .leftToRight)
        .sheet(isPresented: $viewModel.showsAddExpenseSheet) {
            AdminAddExpenseSheet(viewModel: viewModel)
        }
        .sheet(isPresented: $viewModel.showsExportSheet) {
            AdminFinancialExportSheet(viewModel: viewModel)
        }
        .sheet(item: $viewModel.inspectingExpense) { expense in
            AdminExpenseDetailSheet(expense: expense, viewModel: viewModel)
        }
        .sheet(item: $viewModel.inspectingTransaction) { txn in
            AdminTransactionDetailSheet(transaction: txn)
        }
    }

    // MARK: - 1. Sovereign Navigation Bar

    private var commandTelemetryHeader: some View {
        AdminSovereignNavigationBar(
            title: Language.get("Accounting_Title", alter: "المحاسبة والمركز المالي"),
            subtitle: Language.get("Accounting_LiveLedger", alter: "مزامنة حية"),
            statusDotColor: viewModel.evidenceAvailable ? Color(uiColor: .ppSuccess) : Color(uiColor: .ppWarning),
            onBack: {
                if let onDismiss {
                    onDismiss()
                } else {
                    dismiss()
                }
            }
        ) {
            HStack(spacing: 8) {
                // Scope Badge
                HStack(spacing: 4) {
                    Image(systemName: session.hasGlobalScope ? "globe.americas.fill" : "building.2.fill")
                        .font(.system(size: 11, weight: .semibold))
                    Text(session.hasGlobalScope ? Language.get("Accounting_ScopeGlobal", alter: "مركزي") : Language.get("Accounting_ScopeBranch", alter: "فرع"))
                        .font(AdminType.caption2Bold)
                }
                .foregroundColor(AdminSurface.primary)
                .padding(.horizontal, 10)
                .frame(height: 38)
                .background(AdminSurface.primary.opacity(0.10), in: RoundedRectangle(cornerRadius: 12, style: .continuous))

                // Export Button (Matching Back Button Size & Corners: 44x44, radius 14)
                AdminSquircleActionButton(
                    systemImage: "square.and.arrow.up",
                    accessibilityLabel: Language.get("Accounting_ExportSummary", alter: "تصدير الكشف")
                ) {
                    viewModel.showsExportSheet = true
                }

                // Add Expense Button (Matching Back Button Size & Corners: 44x44, radius 14, Icon-Only)
                AdminSquircleActionButton(
                    systemImage: "plus",
                    isPrimary: true,
                    accessibilityLabel: Language.get("Accounting_RecordExpense", alter: "تسجيل مصروف")
                ) {
                    viewModel.showsAddExpenseSheet = true
                }
            }
        }
    }

    // MARK: - 2. Hero Financial Prism

    private var heroBalancePrism: some View {
        ZStack {
            // Background Mesh Surface
            RoundedRectangle(cornerRadius: AdminRadius.hero, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            AdminSurface.control,
                            viewModel.isProfitable
                                ? Color(uiColor: .ppSuccess).opacity(colorScheme == .dark ? 0.12 : 0.08)
                                : Color(uiColor: .ppError).opacity(colorScheme == .dark ? 0.14 : 0.09)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            // Specular Highlight Stroke
            RoundedRectangle(cornerRadius: AdminRadius.hero, style: .continuous)
                .stroke(
                    LinearGradient(
                        colors: [
                            viewModel.isProfitable
                                ? Color(uiColor: .ppSuccess).opacity(0.35)
                                : Color(uiColor: .ppError).opacity(0.35),
                            AdminSurface.hairline
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1.2
                )

            VStack(spacing: 16) {
                // Status Header Row
                HStack(alignment: .center) {
                    HStack(spacing: 6) {
                        Image(systemName: viewModel.isProfitable ? "chart.line.uptrend.xyaxis.circle.fill" : "exclamationmark.triangle.fill")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(viewModel.isProfitable ? Color(uiColor: .ppSuccess) : Color(uiColor: .ppError))
                        Text(viewModel.isProfitable ? Language.get("Accounting_NetProfit", alter: "صافي الربح التشغيلي") : Language.get("Accounting_NetLoss", alter: "عجز تشغيلي"))
                            .font(AdminType.captionBold)
                            .foregroundColor(AdminSurface.secondaryText)
                    }

                    Spacer()

                    // Margin Health Chip
                    HStack(spacing: 5) {
                        Image(systemName: viewModel.isProfitable ? "checkmark.circle.fill" : "arrow.down.circle.fill")
                            .font(.system(size: 10, weight: .bold))
                        Text(String(format: "%.1f%% %@", viewModel.profitMarginPercent, Language.get("Accounting_ProfitMargin", alter: "الهامش")))
                            .font(AdminType.caption2Bold)
                    }
                    .foregroundColor(viewModel.isProfitable ? Color(uiColor: .ppSuccess) : Color(uiColor: .ppError))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(
                        (viewModel.isProfitable ? Color(uiColor: .ppSuccess) : Color(uiColor: .ppError)).opacity(0.12),
                        in: Capsule()
                    )
                }

                // Large Net Operating Figure
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(viewModel.isProfitable ? "+" : "-")
                        .font(.system(size: 32, weight: .bold, design: .rounded))
                        .foregroundColor(viewModel.isProfitable ? Color(uiColor: .ppSuccess) : Color(uiColor: .ppError))

                    Text(PPFormatMoneyString(abs(viewModel.netProfit)))
                        .font(.custom("Beiruti-Bold", size: 36, relativeTo: .largeTitle))
                        .foregroundColor(AdminSurface.primaryText)
                        .minimumScaleFactor(0.70)
                        .lineLimit(1)

                    Spacer()
                }

                // Interactive Cash Inflow / Outflow Visual Split Bar
                VStack(spacing: 6) {
                    GeometryReader { geo in
                        let totalFlow = max(viewModel.grossRevenue + viewModel.totalExpenses, 1.0)
                        let inflowRatio = max(min(CGFloat(viewModel.grossRevenue / totalFlow), 0.96), 0.04)

                        HStack(spacing: 3) {
                            // Inflow Segment
                            RoundedRectangle(cornerRadius: 4, style: .continuous)
                                .fill(
                                    LinearGradient(
                                        colors: [Color(uiColor: .ppSuccess), Color(uiColor: .ppSuccess).opacity(0.80)],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                                .frame(width: geo.size.width * inflowRatio)

                            // Outflow Segment
                            RoundedRectangle(cornerRadius: 4, style: .continuous)
                                .fill(
                                    LinearGradient(
                                        colors: [Color(uiColor: .ppError).opacity(0.80), Color(uiColor: .ppError)],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                                .frame(width: geo.size.width * (1.0 - inflowRatio) - 3)
                        }
                    }
                    .frame(height: 8)

                    // Labels below bar
                    HStack {
                        HStack(spacing: 4) {
                            Circle().fill(Color(uiColor: .ppSuccess)).frame(width: 6, height: 6)
                            Text(Language.get("Accounting_CashInflow", alter: "تدفق داخل"))
                                .font(AdminType.caption2)
                                .foregroundColor(AdminSurface.secondaryText)
                        }
                        Spacer()
                        HStack(spacing: 4) {
                            Circle().fill(Color(uiColor: .ppError)).frame(width: 6, height: 6)
                            Text(Language.get("Accounting_CashOutflow", alter: "تدفق خارج"))
                                .font(AdminType.caption2)
                                .foregroundColor(AdminSurface.secondaryText)
                        }
                    }
                }

                Divider().overlay(AdminSurface.hairline)

                // Bottom Metric Triad
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(Language.get("Accounting_GrossRevenue", alter: "المقبوضات"))
                            .font(AdminType.caption2)
                            .foregroundColor(AdminSurface.secondaryText)
                        Text(PPFormatMoneyString(viewModel.grossRevenue))
                            .font(AdminType.subheadlineBold)
                            .foregroundColor(Color(uiColor: .ppSuccess))
                            .lineLimit(1)
                            .minimumScaleFactor(0.80)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    Divider().frame(height: 28).overlay(AdminSurface.hairline)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(Language.get("Accounting_TotalExpenses", alter: "المصروفات"))
                            .font(AdminType.caption2)
                            .foregroundColor(AdminSurface.secondaryText)
                        Text(PPFormatMoneyString(viewModel.totalExpenses))
                            .font(AdminType.subheadlineBold)
                            .foregroundColor(Color(uiColor: .ppError))
                            .lineLimit(1)
                            .minimumScaleFactor(0.80)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    Divider().frame(height: 28).overlay(AdminSurface.hairline)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(Language.get("Accounting_SettledOrders", alter: "الطلبات"))
                            .font(AdminType.caption2)
                            .foregroundColor(AdminSurface.secondaryText)
                        Text("\(viewModel.paidOrderCount)")
                            .font(AdminType.subheadlineBold)
                            .foregroundColor(AdminSurface.primaryText)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(18)
        }
        .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.28 : 0.05), radius: 14, x: 0, y: 6)
    }

    // MARK: - 3. Fluid Period Selector Matrix

    private var periodSelectorMatrix: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(AccountingPeriod.allCases) { period in
                    let isSelected = viewModel.selectedPeriod == period
                    Button {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        withAnimation(.spring(response: 0.28, dampingFraction: 0.78)) {
                            viewModel.selectedPeriod = period
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: period.symbol)
                                .font(.system(size: 12, weight: isSelected ? .bold : .medium))
                            Text(period.localizedTitle)
                                .font(isSelected ? AdminType.captionBold : AdminType.caption)
                        }
                        .foregroundColor(isSelected ? .white : AdminSurface.primaryText)
                        .padding(.horizontal, 14)
                        .frame(height: 38)
                        .background(
                            isSelected ? AdminSurface.primary : AdminSurface.control,
                            in: Capsule()
                        )
                        .overlay(
                            Capsule().stroke(isSelected ? Color.clear : AdminSurface.hairline)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 2)
        }
    }

    // MARK: - 4. Metric Quadrant Grid

    private var metricQuadrantGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
            // Pod 1: Inflow / Gross Revenue
            metricPod(
                title: Language.get("Accounting_GrossRevenue", alter: "إجمالي الإيرادات"),
                value: PPFormatMoneyString(viewModel.grossRevenue),
                subtitle: String(format: Language.get("Accounting_OrdersCount_Format", alter: Language.isRTL() ? "%@ عملية دخل" : "%@ income entries"), "\(viewModel.paidOrderCount)"),
                symbol: "arrow.up.circle.fill",
                tint: Color(uiColor: .ppSuccess)
            )

            // Pod 2: Outflow / OPEX
            metricPod(
                title: Language.get("Accounting_TotalExpenses", alter: "نفقات التشغيل"),
                value: PPFormatMoneyString(viewModel.totalExpenses),
                subtitle: String(format: Language.get("Accounting_ExpensesCount_Format", alter: "%@ قيد مصروف"), "\(viewModel.expenses.count)"),
                symbol: "arrow.down.circle.fill",
                tint: Color(uiColor: .ppError)
            )

            // Pod 3: Profit Margin %
            metricPod(
                title: Language.get("Accounting_ProfitMargin", alter: "هامش الربح"),
                value: String(format: "%.1f%%", viewModel.profitMarginPercent),
                subtitle: viewModel.isProfitable ? Language.get("Accounting_HealthyMargin", alter: "هامش صحي") : Language.get("Accounting_DeficitAlert", alter: "عجز في التشغيل"),
                symbol: "percent",
                tint: viewModel.isProfitable ? Color(uiColor: .ppSuccess) : Color(uiColor: .ppWarning)
            )

            // Pod 4: Average Order Ticket
            metricPod(
                title: Language.get("Accounting_AverageOrder", alter: "متوسط الطلب"),
                value: PPFormatMoneyString(viewModel.averageOrderValue),
                subtitle: String(format: "%.1f%% %@", viewModel.expenseToRevenueRatio, Language.get("Accounting_ExpenseRatio", alter: "نسبة النفقات")),
                symbol: "cart.circle.fill",
                tint: Color(red: 0.95, green: 0.60, blue: 0.18)
            )
        }
    }

    private func metricPod(title: String, value: String, subtitle: String, symbol: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(tint.opacity(0.12))
                    Image(systemName: symbol)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(tint)
                }
                .frame(width: 32, height: 32)

                Spacer()
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(AdminType.caption2)
                    .foregroundColor(AdminSurface.secondaryText)
                    .lineLimit(1)

                Text(value)
                    .font(AdminType.headline)
                    .foregroundColor(AdminSurface.primaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)

                Text(subtitle)
                    .font(AdminType.caption2)
                    .foregroundColor(AdminSurface.secondaryText)
                    .lineLimit(1)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: AdminRadius.card, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: AdminRadius.card, style: .continuous).stroke(AdminSurface.hairline))
    }

    // MARK: - 5. Category Waterfall Spectrum

    private var categoryWaterfallCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "chart.bar.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(AdminSurface.primary)
                    Text(Language.get("Accounting_OPEXBreakdown", alter: "توزيع تكاليف التشغيل (OPEX)"))
                        .font(AdminType.captionBold)
                        .foregroundColor(AdminSurface.primaryText)
                }
                Spacer()
                Text("\(viewModel.categoryBreakdown.count) \(Language.get("Accounting_CostCenters", alter: "مراكز"))")
                    .font(AdminType.caption2)
                    .foregroundColor(AdminSurface.secondaryText)
            }

            VStack(spacing: 10) {
                ForEach(viewModel.categoryBreakdown.prefix(5)) { item in
                    VStack(spacing: 4) {
                        HStack {
                            HStack(spacing: 6) {
                                Image(systemName: item.config.symbol)
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundColor(item.config.color)
                                Text(item.config.localizedTitle)
                                    .font(AdminType.caption1)
                                    .foregroundColor(AdminSurface.primaryText)
                            }
                            Spacer()
                            Text("\(PPFormatMoneyString(item.totalAmount)) (\(String(format: "%.1f", item.percentage))%)")
                                .font(AdminType.caption2Bold)
                                .foregroundColor(AdminSurface.secondaryText)
                        }

                        // Progress Bar
                        GeometryReader { g in
                            ZStack(alignment: .leading) {
                                RoundedRectangle(cornerRadius: 3, style: .continuous)
                                    .fill(AdminSurface.hairline.opacity(0.3))
                                RoundedRectangle(cornerRadius: 3, style: .continuous)
                                    .fill(item.config.color)
                                    .frame(width: max(g.size.width * CGFloat(item.percentage / 100.0), 4))
                            }
                        }
                        .frame(height: 6)
                    }
                }
            }
        }
        .padding(16)
        .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: AdminRadius.card, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: AdminRadius.card, style: .continuous).stroke(AdminSurface.hairline))
    }

    // MARK: - 6. Mode Switcher Control

    private var modeSegmentedControl: some View {
        HStack(spacing: 4) {
            ForEach(AccountingLedgerMode.allCases) { mode in
                let isSelected = viewModel.selectedLedgerMode == mode
                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.80)) {
                        viewModel.selectedLedgerMode = mode
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: mode.symbol)
                            .font(.system(size: 12, weight: isSelected ? .bold : .medium))
                        Text(mode.localizedTitle)
                            .font(isSelected ? AdminType.captionBold : AdminType.caption)
                    }
                    .foregroundColor(isSelected ? AdminSurface.primary : AdminSurface.secondaryText)
                    .frame(maxWidth: .infinity)
                    .frame(height: 40)
                    .background(
                        isSelected ? AdminSurface.surface : Color.clear,
                        in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(isSelected ? AdminSurface.hairline : Color.clear)
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(AdminSurface.hairline))
    }

    // MARK: - 7. Dynamic Ledger Content

    @ViewBuilder
    private var ledgerContentView: some View {
        switch viewModel.selectedLedgerMode {
        case .ledger:
            transactionsLedgerView
        case .expenses:
            expensesLedgerView
        case .analytics:
            analyticsDeepDiveView
        }
    }

    // MARK: - Sub-View: Transactions Stream

    private var transactionsLedgerView: some View {
        VStack(spacing: 12) {
            // Search Bar
            AdminSearchField(
                text: $viewModel.searchQuery,
                placeholder: Language.get("Accounting_SearchPlaceholder", alter: "بحث في المعاملات...")
            )

            if viewModel.filteredTransactions.isEmpty {
                emptyState(
                    symbol: "arrow.left.arrow.right.circle",
                    title: Language.get("Accounting_NoTransactions", alter: "لا توجد معاملات مسجلة"),
                    subtitle: Language.get("Accounting_NoDataSub", alter: "تأكد من اختيار فترة زمنية مناسبة أو تسجيل معاملات جديدة.")
                )
            } else {
                LazyVStack(spacing: 10) {
                    ForEach(viewModel.filteredTransactions, id: \.txnID) { txn in
                        Button {
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            viewModel.inspectingTransaction = txn
                        } label: {
                            transactionCardRow(txn)
                        }
                        .buttonStyle(V6CardButtonStyle())
                    }
                }
            }
        }
    }

    private func transactionCardRow(_ txn: PPAccountingTransaction) -> some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color(uiColor: .ppSuccess).opacity(0.12))
                Image(systemName: "creditcard.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(Color(uiColor: .ppSuccess))
            }
            .frame(width: 44, height: 44)

            VStack(alignment: .leading, spacing: 3) {
                Text(txn.desc.isEmpty ? "\(Language.get("Accounting_Transaction", alter: "معاملة")) #\(txn.txnID.prefix(8))" : txn.desc)
                    .font(AdminType.calloutBold)
                    .foregroundColor(AdminSurface.primaryText)
                    .lineLimit(1)

                HStack(spacing: 6) {
                    Text(PPFormatDateRelative(txn.createdAt))
                        .font(AdminType.caption2)
                        .foregroundColor(AdminSurface.secondaryText)

                    Text("•")
                        .font(AdminType.caption2)
                        .foregroundColor(AdminSurface.secondaryText)

                    Text(txn.type.isEmpty ? "Settled" : txn.type.uppercased())
                        .font(AdminType.caption2Bold)
                        .foregroundColor(Color(uiColor: .ppSuccess))
                }
            }

            Spacer()

            Text("+\(PPFormatMoneyString(txn.amount))")
                .font(AdminType.calloutBold)
                .foregroundColor(Color(uiColor: .ppSuccess))
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Color(uiColor: .ppSuccess).opacity(0.10), in: Capsule())
        }
        .padding(14)
        .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: AdminRadius.card, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: AdminRadius.card, style: .continuous).stroke(AdminSurface.hairline))
    }

    // MARK: - Sub-View: Expenses Stream

    private var expensesLedgerView: some View {
        VStack(spacing: 12) {
            // Search Bar
            AdminSearchField(
                text: $viewModel.searchQuery,
                placeholder: Language.get("Accounting_SearchPlaceholder", alter: "بحث في المصروفات...")
            )

            // Category Filter Pills
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    let isAll = viewModel.selectedCategoryFilter == nil
                    Button {
                        withAnimation { viewModel.selectedCategoryFilter = nil }
                    } label: {
                        Text(Language.get("Accounting_Filter_All", alter: "الكل"))
                            .font(isAll ? AdminType.captionBold : AdminType.caption)
                            .foregroundColor(isAll ? .white : AdminSurface.primaryText)
                            .padding(.horizontal, 12)
                            .frame(height: 32)
                            .background(isAll ? AdminSurface.primary : AdminSurface.control, in: Capsule())
                            .overlay(Capsule().stroke(isAll ? Color.clear : AdminSurface.hairline))
                    }

                    ForEach(AccountingCategoryConfig.allCategories) { cat in
                        let isCatSelected = viewModel.selectedCategoryFilter == cat.key
                        Button {
                            withAnimation {
                                viewModel.selectedCategoryFilter = isCatSelected ? nil : cat.key
                            }
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: cat.symbol)
                                    .font(.system(size: 10, weight: .bold))
                                Text(cat.localizedTitle)
                                    .font(isCatSelected ? AdminType.captionBold : AdminType.caption)
                            }
                            .foregroundColor(isCatSelected ? .white : AdminSurface.primaryText)
                            .padding(.horizontal, 12)
                            .frame(height: 32)
                            .background(isCatSelected ? cat.color : AdminSurface.control, in: Capsule())
                            .overlay(Capsule().stroke(isCatSelected ? Color.clear : AdminSurface.hairline))
                        }
                    }
                }
            }

            if viewModel.filteredExpenses.isEmpty {
                emptyState(
                    symbol: "arrow.down.circle",
                    title: Language.get("Accounting_NoExpenses", alter: "لا توجد مصروفات مسجلة"),
                    subtitle: Language.get("Accounting_NoDataSub", alter: "سجل مصروفًا جديدًا أو قم بتعديل عامل التصفية."),
                    actionTitle: Language.get("Accounting_RecordExpense", alter: "تسجيل مصروف جديد"),
                    action: { viewModel.showsAddExpenseSheet = true }
                )
            } else {
                LazyVStack(spacing: 10) {
                    ForEach(viewModel.filteredExpenses, id: \.expenseID) { exp in
                        Button {
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            viewModel.inspectingExpense = exp
                        } label: {
                            expenseCardRow(exp)
                        }
                        .buttonStyle(V6CardButtonStyle())
                    }
                }
            }
        }
    }

    private func expenseCardRow(_ exp: PPAccountingExpense) -> some View {
        let catCfg = AccountingCategoryConfig.config(for: exp.category)

        return HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(catCfg.color.opacity(0.14))
                Image(systemName: catCfg.symbol)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(catCfg.color)
            }
            .frame(width: 44, height: 44)

            VStack(alignment: .leading, spacing: 3) {
                Text(exp.desc.isEmpty ? catCfg.localizedTitle : exp.desc)
                    .font(AdminType.calloutBold)
                    .foregroundColor(AdminSurface.primaryText)
                    .lineLimit(1)

                HStack(spacing: 6) {
                    Text(catCfg.localizedTitle)
                        .font(AdminType.caption2Bold)
                        .foregroundColor(catCfg.color)

                    Text("•")
                        .font(AdminType.caption2)
                        .foregroundColor(AdminSurface.secondaryText)

                    Text(PPFormatDateRelative(exp.createdAt))
                        .font(AdminType.caption2)
                        .foregroundColor(AdminSurface.secondaryText)
                }
            }

            Spacer()

            Text("-\(PPFormatMoneyString(exp.amount))")
                .font(AdminType.calloutBold)
                .foregroundColor(Color(uiColor: .ppError))
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Color(uiColor: .ppError).opacity(0.10), in: Capsule())
        }
        .padding(14)
        .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: AdminRadius.card, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: AdminRadius.card, style: .continuous).stroke(AdminSurface.hairline))
    }

    // MARK: - Sub-View: Analytics & Intel

    private var analyticsDeepDiveView: some View {
        VStack(spacing: 14) {
            // Cost Efficiency Card
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Label(Language.get("Accounting_AnalyticsHub", alter: "المؤشرات المالية"), systemImage: "speedometer")
                        .font(AdminType.calloutBold)
                        .foregroundColor(AdminSurface.primaryText)
                    Spacer()
                }

                VStack(spacing: 10) {
                    analyticalRow(
                        title: Language.get("Accounting_GrossRevenue", alter: "إجمالي المقبوضات"),
                        value: PPFormatMoneyString(viewModel.grossRevenue),
                        tint: Color(uiColor: .ppSuccess)
                    )
                    Divider().overlay(AdminSurface.hairline)
                    analyticalRow(
                        title: Language.get("Accounting_TotalExpenses", alter: "إجمالي المصروفات"),
                        value: PPFormatMoneyString(viewModel.totalExpenses),
                        tint: Color(uiColor: .ppError)
                    )
                    Divider().overlay(AdminSurface.hairline)
                    analyticalRow(
                        title: Language.get("Accounting_NetProfit", alter: "صافي الأرباح التشغيلية"),
                        value: PPFormatMoneyString(viewModel.netProfit),
                        tint: viewModel.isProfitable ? Color(uiColor: .ppSuccess) : Color(uiColor: .ppError)
                    )
                    Divider().overlay(AdminSurface.hairline)
                    analyticalRow(
                        title: Language.get("Accounting_ProfitMargin", alter: "هامش الربح التشغيلي"),
                        value: String(format: "%.2f%%", viewModel.profitMarginPercent),
                        tint: viewModel.isProfitable ? Color(uiColor: .ppSuccess) : Color(uiColor: .ppWarning)
                    )
                    Divider().overlay(AdminSurface.hairline)
                    analyticalRow(
                        title: Language.get("Accounting_ExpenseRatio", alter: "نسبة النفقات للإيراد"),
                        value: String(format: "%.1f%%", viewModel.expenseToRevenueRatio),
                        tint: viewModel.expenseToRevenueRatio < 70 ? Color(uiColor: .ppSuccess) : Color(uiColor: .ppWarning)
                    )
                }
            }
            .padding(16)
            .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: AdminRadius.card, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: AdminRadius.card, style: .continuous).stroke(AdminSurface.hairline))

            // Audit Assurance Notice
            HStack(spacing: 12) {
                Image(systemName: "checkmark.shield.fill")
                    .font(.system(size: 22))
                    .foregroundColor(Color(uiColor: .ppSuccess))
                VStack(alignment: .leading, spacing: 2) {
                    Text(Language.get("Accounting_AuditNotice", alter: "نظام القيود المالية مرتبط بتدقيق موظفي المنصة المعتمدين."))
                        .font(AdminType.caption)
                        .foregroundColor(AdminSurface.secondaryText)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(uiColor: .ppSuccess).opacity(0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Color(uiColor: .ppSuccess).opacity(0.20)))
        }
    }

    private func analyticalRow(title: String, value: String, tint: Color) -> some View {
        HStack {
            Text(title)
                .font(AdminType.callout)
                .foregroundColor(AdminSurface.secondaryText)
            Spacer()
            Text(value)
                .font(AdminType.calloutBold)
                .foregroundColor(tint)
        }
    }

    // MARK: - Reusable Empty State

    private func emptyState(symbol: String, title: String, subtitle: String, actionTitle: String? = nil, action: (() -> Void)? = nil) -> some View {
        VStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 38, weight: .light))
                .foregroundColor(AdminSurface.secondaryText.opacity(0.40))
                .padding(.top, 24)

            Text(title)
                .font(AdminType.headline)
                .foregroundColor(AdminSurface.primaryText)

            Text(subtitle)
                .font(AdminType.callout)
                .foregroundColor(AdminSurface.secondaryText)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)

            if let actionTitle, let action {
                Button(action: action) {
                    Text(actionTitle)
                        .font(AdminType.captionBold)
                        .foregroundColor(.white)
                        .padding(.horizontal, 20)
                        .frame(height: 42)
                        .background(AdminSurface.primary, in: Capsule())
                }
                .padding(.top, 6)
            }
        }
        .padding(.bottom, 32)
        .frame(maxWidth: .infinity)
        .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: AdminRadius.card, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: AdminRadius.card, style: .continuous).stroke(AdminSurface.hairline))
    }
}

// MARK: - Sheet 1: Tactile Expense Creation Studio

struct AdminAddExpenseSheet: View {
    @ObservedObject var viewModel: AccountingViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var amountText: String = ""
    @State private var selectedCategory: String = "supplies"
    @State private var descriptionText: String = ""
    @State private var isSubmitting: Bool = false
    @State private var validationError: String? = nil

    var body: some View {
        NavigationView {
            ZStack {
                AdminSurface.background.ignoresSafeArea()

                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 20) {
                        // Amount Keypad Header
                        amountInputCard

                        // Category Selector Grid
                        categoryGridCard

                        // Note / Description Field
                        noteFieldCard

                        // Staff Audit Assurance Card
                        auditAssuranceNotice

                        // Submit Button
                        submitButton
                    }
                    .padding(AdminSpacing.screenMargin)
                    .padding(.bottom, 24)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(Language.get("Cancel", alter: "إلغاء")) {
                        dismiss()
                    }
                    .foregroundColor(AdminSurface.secondaryText)
                }
                ToolbarItem(placement: .principal) {
                    Text(Language.get("Accounting_ExpenseStudioTitle", alter: "تسجيل قيد مصروف"))
                        .font(AdminType.headline)
                        .foregroundColor(AdminSurface.primaryText)
                }
            }
        }
        .environment(\.layoutDirection, Language.isRTL() ? .rightToLeft : .leftToRight)
    }

    private var amountInputCard: some View {
        VStack(spacing: 8) {
            Text(Language.get("Accounting_Amount", alter: "المبلغ المطلوب قيده"))
                .font(AdminType.captionBold)
                .foregroundColor(AdminSurface.secondaryText)

            HStack(alignment: .firstTextBaseline, spacing: 6) {
                TextField("0.00", text: $amountText)
                    .keyboardType(.decimalPad)
                    .font(.custom("Beiruti-Bold", size: 42, relativeTo: .largeTitle))
                    .foregroundColor(AdminSurface.primaryText)
                    .multilineTextAlignment(.center)
                    .frame(minHeight: 54)

                Text(Language.get("Accounting_QAR", alter: "ر.ق"))
                    .font(AdminType.headline)
                    .foregroundColor(AdminSurface.primary)
            }

            if let error = validationError {
                Text(error)
                    .font(AdminType.caption)
                    .foregroundColor(Color(uiColor: .ppError))
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity)
        .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: AdminRadius.card, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: AdminRadius.card, style: .continuous).stroke(AdminSurface.hairline))
    }

    private var categoryGridCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(Language.get("Accounting_Category", alter: "تصنيف المصروف"))
                .font(AdminType.captionBold)
                .foregroundColor(AdminSurface.secondaryText)

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                ForEach(AccountingCategoryConfig.allCategories) { cat in
                    let isSelected = selectedCategory == cat.key
                    Button {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        selectedCategory = cat.key
                    } label: {
                        HStack(spacing: 8) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(cat.color.opacity(isSelected ? 0.95 : 0.14))
                                Image(systemName: cat.symbol)
                                    .font(.system(size: 13, weight: .bold))
                                    .foregroundColor(isSelected ? .white : cat.color)
                            }
                            .frame(width: 28, height: 28)

                            Text(cat.localizedTitle)
                                .font(isSelected ? AdminType.captionBold : AdminType.caption)
                                .foregroundColor(isSelected ? AdminSurface.primaryText : AdminSurface.secondaryText)
                                .lineLimit(1)
                                .minimumScaleFactor(0.85)

                            Spacer()

                            if isSelected {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundColor(AdminSurface.primary)
                            }
                        }
                        .padding(10)
                        .background(
                            isSelected ? cat.color.opacity(0.12) : AdminSurface.surface,
                            in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(isSelected ? cat.color : AdminSurface.hairline, lineWidth: isSelected ? 1.5 : 0.75)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(16)
        .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: AdminRadius.card, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: AdminRadius.card, style: .continuous).stroke(AdminSurface.hairline))
    }

    private var noteFieldCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(Language.get("Accounting_Description", alter: "البيان / الملاحظة"))
                .font(AdminType.captionBold)
                .foregroundColor(AdminSurface.secondaryText)

            TextField(Language.get("Accounting_DescriptionPlaceholder", alter: "اكتب وصف المصروف أو سبب الصرف..."), text: $descriptionText)
                .font(AdminType.callout)
                .foregroundColor(AdminSurface.primaryText)
                .padding(12)
                .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(AdminSurface.hairline))
        }
        .padding(16)
        .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: AdminRadius.card, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: AdminRadius.card, style: .continuous).stroke(AdminSurface.hairline))
    }

    private var auditAssuranceNotice: some View {
        HStack(spacing: 10) {
            Image(systemName: "lock.shield.fill")
                .font(.system(size: 18))
                .foregroundColor(AdminSurface.primary)
            Text(Language.get("Accounting_AuditNotice", alter: "موثق بالتدقيق: سيتم ربط هذا القيد بهويتك الإدارية وصلاحياتك."))
                .font(AdminType.caption2)
                .foregroundColor(AdminSurface.secondaryText)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AdminSurface.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private var submitButton: some View {
        Button {
            submitExpense()
        } label: {
            HStack(spacing: 8) {
                if isSubmitting {
                    ProgressView().tint(.white)
                } else {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 16, weight: .bold))
                }
                Text(Language.get("Accounting_RecordExpense", alter: "تسجيل القيد المالي"))
                    .font(AdminType.headline)
            }
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .background(AdminSurface.primary, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .shadow(color: AdminSurface.primary.opacity(0.35), radius: 8, x: 0, y: 4)
        }
        .disabled(isSubmitting)
    }

    private func submitExpense() {
        let clean = amountText.replacingOccurrences(of: ",", with: ".")
        guard let amt = Double(clean), amt > 0 else {
            validationError = Language.get("Accounting_InvalidAmount", alter: "يرجى إدخال مبلغ صحيح أكبر من صفر.")
            UINotificationFeedbackGenerator().notificationOccurred(.error)
            return
        }

        validationError = nil
        isSubmitting = true

        viewModel.addExpense(amount: amt, category: selectedCategory, description: descriptionText) { result in
            isSubmitting = false
            switch result {
            case .success:
                dismiss()
            case .failure(let error):
                validationError = error.localizedDescription
                UINotificationFeedbackGenerator().notificationOccurred(.error)
            }
        }
    }
}

// MARK: - Sheet 2: Digital Expense Voucher Dossier

struct AdminExpenseDetailSheet: View {
    let expense: PPAccountingExpense
    @ObservedObject var viewModel: AccountingViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var showsVoidConfirmation: Bool = false
    @State private var isVoiding: Bool = false

    var body: some View {
        NavigationView {
            ZStack {
                AdminSurface.background.ignoresSafeArea()

                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 20) {
                        // Digital Voucher Card
                        voucherCard

                        // Destructive Void Action
                        voidRecordButton
                    }
                    .padding(AdminSpacing.screenMargin)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(Language.get("Accounting_Close", alter: "إغلاق")) {
                        dismiss()
                    }
                    .foregroundColor(AdminSurface.primary)
                }
                ToolbarItem(placement: .principal) {
                    Text(Language.get("Accounting_ExpenseDetails", alter: "تفاصيل مستند المصروف"))
                        .font(AdminType.headline)
                        .foregroundColor(AdminSurface.primaryText)
                }
            }
        }
        .environment(\.layoutDirection, Language.isRTL() ? .rightToLeft : .leftToRight)
    }

    private var voucherCard: some View {
        let catCfg = AccountingCategoryConfig.config(for: expense.category)

        return VStack(spacing: 16) {
            // Category Badge & Icon
            ZStack {
                Circle().fill(catCfg.color.opacity(0.15)).frame(width: 60, height: 60)
                Image(systemName: catCfg.symbol)
                    .font(.system(size: 24, weight: .bold))
                    .foregroundColor(catCfg.color)
            }
            .padding(.top, 10)

            Text(catCfg.localizedTitle)
                .font(AdminType.headline)
                .foregroundColor(AdminSurface.primaryText)

            Text("-\(PPFormatMoneyString(expense.amount))")
                .font(.custom("Beiruti-Bold", size: 38, relativeTo: .largeTitle))
                .foregroundColor(Color(uiColor: .ppError))

            Divider().overlay(AdminSurface.hairline)

            VStack(spacing: 12) {
                voucherRow(
                    title: Language.get("Accounting_VoucherID", alter: "رقم المستند"),
                    value: expense.expenseID,
                    isMonospace: true
                )

                voucherRow(
                    title: Language.get("Accounting_Description", alter: "الوصف والبيان"),
                    value: expense.desc.isEmpty ? "-" : expense.desc
                )

                voucherRow(
                    title: Language.get("Accounting_RecordedBy", alter: "الموظف المسجل"),
                    value: expense.createdBy.isEmpty ? "System" : expense.createdBy,
                    isMonospace: true
                )

                voucherRow(
                    title: Language.get("Accounting_Timestamp", alter: "التاريخ والوقت"),
                    value: expense.createdAt != nil ? DateFormatter.localizedString(from: expense.createdAt!, dateStyle: .medium, timeStyle: .short) : "-"
                )

                voucherRow(
                    title: Language.get("Accounting_LedgerStatus", alter: "حالة القيد"),
                    value: Language.get("Accounting_StatusActive", alter: "نشط ومعتمد في الدفتر"),
                    tint: Color(uiColor: .ppSuccess)
                )
            }
        }
        .padding(20)
        .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: AdminRadius.card, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: AdminRadius.card, style: .continuous).stroke(AdminSurface.hairline))
    }

    private func voucherRow(title: String, value: String, isMonospace: Bool = false, tint: Color? = nil) -> some View {
        HStack(alignment: .top) {
            Text(title)
                .font(AdminType.callout)
                .foregroundColor(AdminSurface.secondaryText)
                .frame(width: 110, alignment: .leading)

            Spacer()

            Text(value)
                .font(isMonospace ? .system(size: 13, design: .monospaced) : AdminType.calloutBold)
                .foregroundColor(tint ?? AdminSurface.primaryText)
                .multilineTextAlignment(.trailing)
        }
    }

    private var voidRecordButton: some View {
        Button(role: .destructive) {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            confirmVoidExpense()
        } label: {
            HStack(spacing: 8) {
                if isVoiding {
                    ProgressView().tint(Color(uiColor: .ppError))
                } else {
                    Image(systemName: "trash.fill")
                }
                Text(Language.get("Accounting_VoidExpense", alter: "إلغاء قيد هذا المصروف"))
                    .font(AdminType.calloutBold)
            }
            .foregroundColor(Color(uiColor: .ppError))
            .frame(maxWidth: .infinity)
            .frame(height: 50)
            .background(Color(uiColor: .ppError).opacity(0.10), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .disabled(isVoiding)
    }

    private func confirmVoidExpense() {
        PPAlertHelper.showConfirmation(
            in: nil,
            title: Language.get("Accounting_VoidExpense", alter: "إلغاء القيد المالي"),
            subtitle: Language.get("Accounting_DeleteExpenseConfirm", alter: "هل أنت متأكد من رغبتك في إلغاء قيد هذا المصروف؟"),
            confirmButton: Language.get("Accounting_VoidExpense", alter: "تأكيد الإلغاء"),
            cancelButton: Language.get("Cancel", alter: "إلغاء"),
            icon: UIImage(systemName: "trash.fill"),
            confirmBlock: { _, didConfirm in
                guard didConfirm else { return }
                executeVoid()
            },
            cancelBlock: nil
        )
    }

    private func executeVoid() {
        isVoiding = true
        viewModel.voidExpense(expenseID: expense.expenseID) { result in
            isVoiding = false
            switch result {
            case .success:
                dismiss()
            case .failure:
                break
            }
        }
    }
}

// MARK: - Sheet 3: Transaction Audit Dossier

struct AdminTransactionDetailSheet: View {
    let transaction: PPAccountingTransaction
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            ZStack {
                AdminSurface.background.ignoresSafeArea()

                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 18) {
                        ZStack {
                            Circle().fill(Color(uiColor: .ppSuccess).opacity(0.15)).frame(width: 60, height: 60)
                            Image(systemName: "checkmark.seal.fill")
                                .font(.system(size: 26, weight: .bold))
                                .foregroundColor(Color(uiColor: .ppSuccess))
                        }
                        .padding(.top, 10)

                        Text("+\(PPFormatMoneyString(transaction.amount))")
                            .font(.custom("Beiruti-Bold", size: 38, relativeTo: .largeTitle))
                            .foregroundColor(Color(uiColor: .ppSuccess))

                        VStack(spacing: 12) {
                            txnRow(title: Language.get("Accounting_Transaction", alter: "معرف المعاملة"), value: transaction.txnID, isMonospace: true)
                            txnRow(title: Language.get("Accounting_Description", alter: "البيان"), value: transaction.desc.isEmpty ? "-" : transaction.desc)
                            txnRow(title: Language.get("Accounting_LedgerStatus", alter: "نوع القيد"), value: transaction.type.isEmpty ? "Settled" : transaction.type.uppercased(), tint: Color(uiColor: .ppSuccess))
                            txnRow(title: Language.get("Accounting_Timestamp", alter: "التاريخ والوقت"), value: transaction.createdAt != nil ? DateFormatter.localizedString(from: transaction.createdAt!, dateStyle: .medium, timeStyle: .short) : "-")
                        }
                        .padding(18)
                        .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: AdminRadius.card, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: AdminRadius.card, style: .continuous).stroke(AdminSurface.hairline))
                    }
                    .padding(AdminSpacing.screenMargin)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(Language.get("Accounting_Close", alter: "إغلاق")) {
                        dismiss()
                    }
                    .foregroundColor(AdminSurface.primary)
                }
                ToolbarItem(placement: .principal) {
                    Text(Language.get("Accounting_TxnDetails", alter: "تفاصيل المعاملة"))
                        .font(AdminType.headline)
                        .foregroundColor(AdminSurface.primaryText)
                }
            }
        }
        .environment(\.layoutDirection, Language.isRTL() ? .rightToLeft : .leftToRight)
    }

    private func txnRow(title: String, value: String, isMonospace: Bool = false, tint: Color? = nil) -> some View {
        HStack(alignment: .top) {
            Text(title)
                .font(AdminType.callout)
                .foregroundColor(AdminSurface.secondaryText)
                .frame(width: 110, alignment: .leading)

            Spacer()

            Text(value)
                .font(isMonospace ? .system(size: 13, design: .monospaced) : AdminType.calloutBold)
                .foregroundColor(tint ?? AdminSurface.primaryText)
                .multilineTextAlignment(.trailing)
        }
    }
}

// MARK: - Sheet 4: Executive Financial Statement Exporter

struct AdminFinancialExportSheet: View {
    @ObservedObject var viewModel: AccountingViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var copied: Bool = false

    var body: some View {
        NavigationView {
            ZStack {
                AdminSurface.background.ignoresSafeArea()

                VStack(spacing: 16) {
                    ScrollView(.vertical, showsIndicators: true) {
                        Text(viewModel.generatePLStatementText())
                            .font(.system(size: 13, weight: .regular, design: .monospaced))
                            .foregroundColor(AdminSurface.primaryText)
                            .padding(16)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: AdminRadius.card, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: AdminRadius.card, style: .continuous).stroke(AdminSurface.hairline))
                    }

                    // Action Buttons
                    HStack(spacing: 12) {
                        Button {
                            UIPasteboard.general.string = viewModel.generatePLStatementText()
                            UINotificationFeedbackGenerator().notificationOccurred(.success)
                            withAnimation { copied = true }
                            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                                withAnimation { copied = false }
                            }
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: copied ? "checkmark.circle.fill" : "doc.on.doc.fill")
                                Text(copied ? Language.get("Accounting_ExportSuccess", alter: "تم النسخ!") : Language.get("Accounting_CopyStatement", alter: "نسخ الكشف"))
                            }
                            .font(AdminType.calloutBold)
                            .foregroundColor(copied ? Color(uiColor: .ppSuccess) : AdminSurface.primary)
                            .frame(maxWidth: .infinity)
                            .frame(height: 48)
                            .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(copied ? Color(uiColor: .ppSuccess) : AdminSurface.primary))
                        }

                        Button {
                            shareStatement()
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "square.and.arrow.up.fill")
                                Text(Language.get("Accounting_ShareStatement", alter: "مشاركة الكشف"))
                            }
                            .font(AdminType.calloutBold)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 48)
                            .background(AdminSurface.primary, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }
                    }
                }
                .padding(AdminSpacing.screenMargin)
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(Language.get("Accounting_Close", alter: "إغلاق")) {
                        dismiss()
                    }
                    .foregroundColor(AdminSurface.primary)
                }
                ToolbarItem(placement: .principal) {
                    Text(Language.get("Accounting_ExportSummary", alter: "كشف الأرباح والخسائر"))
                        .font(AdminType.headline)
                        .foregroundColor(AdminSurface.primaryText)
                }
            }
        }
        .environment(\.layoutDirection, Language.isRTL() ? .rightToLeft : .leftToRight)
    }

    private func shareStatement() {
        let text = viewModel.generatePLStatementText()
        let avc = UIActivityViewController(activityItems: [text], applicationActivities: nil)
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let root = windowScene.windows.first(where: { $0.isKeyWindow })?.rootViewController {
            root.present(avc, animated: true)
        }
    }
}
