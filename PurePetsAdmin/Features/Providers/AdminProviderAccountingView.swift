//
//  AdminProviderAccountingView.swift
//  PurePetsAdmin
//
//  Reimagined from absolute first principles for PurePets Flagship Admin.
//  Category-defining Server Ledger & Commission Accounting Interface (MIS-CTL).
//

import SwiftUI
import UIKit

// MARK: - Models

public struct ProviderLedgerSummary: Sendable {
    public let currency: String
    public let totalSales: Double
    public let platformShare: Double
    public let providerNet: Double
    public let pendingBalance: Double
    public let settledBalance: Double
    public let voidedSales: Double
    public let voidedPlatformShare: Double
    public let count: Int

    public var effectiveTakeRate: Double {
        totalSales > 0 ? (platformShare / totalSales) * 100.0 : 0.0
    }

    public var providerRatio: Double {
        totalSales > 0 ? min(max(providerNet / totalSales, 0.0), 1.0) : 0.85
    }

    public static func parse(from totals: [[AnyHashable: Any]], rowCount: Int) -> ProviderLedgerSummary {
        var totalSales = 0.0
        var platformShare = 0.0
        var providerNet = 0.0
        var pendingBalance = 0.0
        var settledBalance = 0.0
        var voidedSales = 0.0
        var voidedPlatformShare = 0.0
        var currency = "QAR"

        for dict in totals {
            if let c = dict["currency"] as? String, !c.isEmpty { currency = c }
            totalSales += (dict["totalSales"] as? NSNumber)?.doubleValue ?? 0.0
            platformShare += (dict["platformShare"] as? NSNumber)?.doubleValue ?? 0.0
            providerNet += (dict["providerNet"] as? NSNumber)?.doubleValue ?? 0.0
            pendingBalance += (dict["pendingBalance"] as? NSNumber)?.doubleValue ?? 0.0
            settledBalance += (dict["settledBalance"] as? NSNumber)?.doubleValue ?? 0.0
            voidedSales += (dict["voidedSales"] as? NSNumber)?.doubleValue ?? 0.0
            voidedPlatformShare += (dict["voidedPlatformShare"] as? NSNumber)?.doubleValue ?? 0.0
        }

        return ProviderLedgerSummary(
            currency: currency,
            totalSales: totalSales,
            platformShare: platformShare,
            providerNet: providerNet,
            pendingBalance: pendingBalance,
            settledBalance: settledBalance,
            voidedSales: voidedSales,
            voidedPlatformShare: voidedPlatformShare,
            count: rowCount
        )
    }
}

public struct ProviderIdentityItem: Identifiable, Hashable, Sendable {
    public let id: String
    public let name: String
    public let providerType: String
    public let status: String
    public let phone: String?

    public init(id: String, name: String, providerType: String, status: String, phone: String? = nil) {
        self.id = id
        self.name = name
        self.providerType = providerType
        self.status = status
        self.phone = phone
    }
}

public enum LedgerStatusFilter: String, CaseIterable, Sendable {
    case all
    case settled
    case pending
    case voided

    public var title: String {
        switch self {
        case .all: return Language.get("All", alter: "الكل")
        case .settled: return Language.get("Settled", alter: "مسواة")
        case .pending: return Language.get("Pending", alter: "قيد المعالجة")
        case .voided: return Language.get("Voided", alter: "ملغاة")
        }
    }

    public var icon: String {
        switch self {
        case .all: return "tray.full.fill"
        case .settled: return "checkmark.seal.fill"
        case .pending: return "clock.arrow.circlepath"
        case .voided: return "xmark.octagon.fill"
        }
    }

    public var color: Color {
        switch self {
        case .all: return AdminSurface.primary
        case .settled: return Color(red: 0.08, green: 0.74, blue: 0.48)
        case .pending: return Color(red: 0.96, green: 0.62, blue: 0.14)
        case .voided: return Color(red: 0.94, green: 0.28, blue: 0.34)
        }
    }
}

public enum LedgerSortOption: String, CaseIterable, Sendable {
    case newest
    case highest
    case oldest

    public var title: String {
        switch self {
        case .newest: return Language.get("Sort_Newest", alter: "الأحدث أولاً")
        case .highest: return Language.get("Sort_HighestValue", alter: "الأعلى قيمة")
        case .oldest: return Language.get("Sort_Oldest", alter: "الأقدم")
        }
    }
}

// MARK: - View Model

@MainActor
public final class ProviderAccountingViewModel: ObservableObject {
    @Published public var inputProviderID: String = ""
    @Published public var currentProviderID: String = ""
    @Published public var currentIdentity: ProviderIdentityItem? = nil
    @Published public var records: [PPProviderCommissionRecord] = []
    @Published public var summary: ProviderLedgerSummary? = nil
    @Published public var isLoading: Bool = false
    @Published public var isRefreshing: Bool = false
    @Published public var errorMessage: String? = nil
    @Published public var selectedFilter: LedgerStatusFilter = .all
    @Published public var inLedgerSearchText: String = ""
    @Published public var sortOption: LedgerSortOption = .newest
    @Published public var verifiedProviders: [ProviderIdentityItem] = []
    @Published public var recentProviderIDs: [String] = []
    @Published public var isChangingProvider: Bool = false
    @Published public var expandedRecordIDs: Set<String> = []
    @Published public var toastMessage: String? = nil
    @Published public var showToast: Bool = false

    private let recentKey = "PPProviderAccountingRecentListKey"
    private let lastKey = "PPProviderAccountingLastProviderID"

    public init(initialProviderID: String? = nil) {
        loadRecents()
        fetchApprovedProviders()

        let target = initialProviderID?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let target, !target.isEmpty {
            inputProviderID = target
            loadReport(for: target)
        } else if let last = UserDefaults.standard.string(forKey: lastKey), !last.isEmpty {
            inputProviderID = last
            loadReport(for: last)
        } else {
            isChangingProvider = true
        }
    }

    public func loadRecents() {
        recentProviderIDs = UserDefaults.standard.stringArray(forKey: recentKey) ?? []
    }

    public func saveRecent(providerID: String) {
        var recents = recentProviderIDs.filter { $0 != providerID }
        recents.insert(providerID, at: 0)
        if recents.count > 6 { recents = Array(recents.prefix(6)) }
        recentProviderIDs = recents
        UserDefaults.standard.set(recents, forKey: recentKey)
        UserDefaults.standard.set(providerID, forKey: lastKey)
    }

    public func fetchApprovedProviders() {
        PPProviderService.shared().fetchApplications { [weak self] apps, _ in
            let verified = apps.filter { $0.status.lowercased() == "approved" }
            let items: [ProviderIdentityItem] = verified.compactMap { app in
                let id = app.userId.isEmpty ? app.applicationID : app.userId
                guard !id.isEmpty else { return nil }
                var name = app.form["storeName"] as? String
                    ?? app.form["name"] as? String
                    ?? app.form["businessName"] as? String
                    ?? app.userSummary["displayName"] as? String
                    ?? ""
                if name.isEmpty { name = id }
                let phone = app.form["phone"] as? String ?? app.userSummary["phoneNumber"] as? String
                return ProviderIdentityItem(
                    id: id,
                    name: name,
                    providerType: app.providerType,
                    status: app.status,
                    phone: phone
                )
            }
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.verifiedProviders = items
                self.correlateCurrentIdentity()
            }
        }
    }

    public func correlateCurrentIdentity() {
        guard !currentProviderID.isEmpty else {
            currentIdentity = nil
            return
        }
        if let match = verifiedProviders.first(where: { $0.id == currentProviderID }) {
            currentIdentity = match
        } else {
            currentIdentity = ProviderIdentityItem(
                id: currentProviderID,
                name: currentProviderID,
                providerType: "marketplace",
                status: "active"
            )
        }
    }

    public func loadReport(for providerID: String) {
        let cleanID = providerID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanID.isEmpty else {
            triggerToast(Language.get("Providers_Accounting_ProviderRequired", alter: "أدخل معرّف المزود أولاً"))
            return
        }

        withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
            isLoading = true
            errorMessage = nil
            currentProviderID = cleanID
            inputProviderID = cleanID
            isChangingProvider = false
        }
        correlateCurrentIdentity()
        saveRecent(providerID: cleanID)

        PPProviderService.shared().fetchCommissionReport(forProviderID: cleanID) { [weak self] fetchedRecords, fetchedTotals, error in
            let parsedSummary: ProviderLedgerSummary?
            if error == nil {
                let dicts = (fetchedTotals as? [[AnyHashable: Any]]) ?? []
                parsedSummary = ProviderLedgerSummary.parse(from: dicts, rowCount: fetchedRecords.count)
            } else {
                parsedSummary = nil
            }
            let errText = error?.localizedDescription

            DispatchQueue.main.async {
                guard let self = self else { return }
                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                    self.isLoading = false
                    self.isRefreshing = false
                    if let errText = errText {
                        self.errorMessage = errText
                        self.records = []
                        self.summary = nil
                    } else {
                        self.records = fetchedRecords
                        self.summary = parsedSummary
                        self.correlateCurrentIdentity()
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    }
                }
            }
        }
    }

    public func refreshCurrent() {
        guard !currentProviderID.isEmpty else { return }
        isRefreshing = true
        loadReport(for: currentProviderID)
    }

    public var filteredRecords: [PPProviderCommissionRecord] {
        var list = records

        switch selectedFilter {
        case .all:
            break
        case .settled:
            list = list.filter { $0.status.lowercased() == "settled" }
        case .pending:
            list = list.filter { $0.status.lowercased() == "pending" }
        case .voided:
            list = list.filter { $0.status.lowercased() == "voided" }
        }

        let query = inLedgerSearchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if !query.isEmpty {
            list = list.filter { record in
                record.orderID.lowercased().contains(query)
                    || record.recordID.lowercased().contains(query)
                    || (record.fulfillmentID.lowercased().contains(query))
            }
        }

        switch sortOption {
        case .newest:
            list.sort { ($0.createdAt ?? .distantPast) > ($1.createdAt ?? .distantPast) }
        case .oldest:
            list.sort { ($0.createdAt ?? .distantPast) < ($1.createdAt ?? .distantPast) }
        case .highest:
            list.sort { $0.grossSaleAmount > $1.grossSaleAmount }
        }

        return list
    }

    public func toggleExpansion(for recordID: String) {
        UISelectionFeedbackGenerator().selectionChanged()
        withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
            if expandedRecordIDs.contains(recordID) {
                expandedRecordIDs.remove(recordID)
            } else {
                expandedRecordIDs.insert(recordID)
            }
        }
    }

    public func copyRecordSummary(_ record: PPProviderCommissionRecord) {
        let text = """
        قيد دفتر الأستاذ المالي • PurePets MIS-CTL
        • رقم القيد: \(record.recordID)
        • الطلب المرجعي: \(record.orderID.isEmpty ? "—" : record.orderID)
        • إجمالي البيع: \(formatMoney(record.grossSaleAmount, currency: record.currency))
        • حصة المنصة (\(String(format: "%.1f", record.commissionRate * 100))%): \(formatMoney(record.platformCommissionAmount, currency: record.currency))
        • صافي المزود: \(formatMoney(record.providerNetAmount, currency: record.currency))
        • الحالة: \(record.status)
        • التوقيت: \(formatDate(record.createdAt))
        """
        UIPasteboard.general.string = text
        triggerToast(Language.get("Copied_To_Clipboard", alter: "تم نسخ تفاصيل القيد المالي"))
    }

    public func copyExecutiveSummary() {
        guard let s = summary else { return }
        let name = currentIdentity?.name ?? currentProviderID
        let text = """
        تقرير دفتر أستاذ العمولات • PurePets Flagship MIS-CTL
        ━━━━━━━━━━━━━━━━━━━━━━━━━━
        المزود: \(name) (\(currentProviderID))
        عدد العمليات: \(s.count) قيداً مصدقاً
        إجمالي المبيعات: \(formatMoney(s.totalSales, currency: s.currency))
        صافي استحقاق المزود: \(formatMoney(s.providerNet, currency: s.currency))
        عمولات المنصة: \(formatMoney(s.platformShare, currency: s.currency))
        الرصيد المسوى: \(formatMoney(s.settledBalance, currency: s.currency))
        الرصيد المعلق: \(formatMoney(s.pendingBalance, currency: s.currency))
        ━━━━━━━━━━━━━━━━━━━━━━━━━━
        دليل مالي خادم محصّن للقراءة فقط • READONLY_SERVER_LEDGER
        """
        UIPasteboard.general.string = text
        triggerToast(Language.get("Copied_To_Clipboard", alter: "تم نسخ التقرير المالي للأستاذ بنجاح"))
    }

    public func triggerToast(_ message: String) {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
            toastMessage = message
            showToast = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
            withAnimation(.easeOut(duration: 0.25)) {
                self.showToast = false
            }
        }
    }

    public func formatMoney(_ amount: Double, currency: String? = nil) -> String {
        let curr = currency ?? summary?.currency ?? "QAR"
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        let formatted = formatter.string(from: NSNumber(value: amount)) ?? String(format: "%.2f", amount)
        return "\(formatted) \(curr)"
    }

    public func formatDate(_ date: Date?) -> String {
        guard let date = date else { return "—" }
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        formatter.locale = Locale(identifier: Language.isRTL() ? "ar_QA" : "en_US")
        return formatter.string(from: date)
    }
}

// MARK: - Main Flagship View

public struct AdminProviderAccountingView: View {
    @StateObject private var viewModel: ProviderAccountingViewModel
    private let isEmbeddedInTab: Bool
    private let onDismiss: (() -> Void)?

    public init(
        initialProviderID: String? = nil,
        isEmbeddedInTab: Bool = false,
        onDismiss: (() -> Void)? = nil
    ) {
        _viewModel = StateObject(wrappedValue: ProviderAccountingViewModel(initialProviderID: initialProviderID))
        self.isEmbeddedInTab = isEmbeddedInTab
        self.onDismiss = onDismiss
    }

    public var body: some View {
        GeometryReader { geometry in
            let isRegular = geometry.size.width >= 700
            let maxDeckWidth: CGFloat = isRegular ? 980 : geometry.size.width
            let horizontalMargin: CGFloat = isRegular ? max((geometry.size.width - maxDeckWidth) / 2, AdminSpacing.screenMargin) : AdminSpacing.screenMargin

            ZStack(alignment: .bottom) {
                AdminSurface.background.ignoresSafeArea()

                VStack(spacing: 0) {
                    if !isEmbeddedInTab {
                        sovereignNavigationBar
                    } else {
                        embeddedTabBar
                    }

                    ScrollView(.vertical, showsIndicators: false) {
                        VStack(spacing: 16) {
                            providerRadarCapsule

                            if viewModel.isLoading {
                                shimmerLoadingSkeleton
                            } else if let error = viewModel.errorMessage {
                                errorStateCard(message: error)
                            } else if viewModel.currentProviderID.isEmpty {
                                zeroStateWelcomeHero
                            } else if let summary = viewModel.summary {
                                apexTelemetryHero(summary: summary, isRegular: isRegular)
                                ledgerControlsStrip(isRegular: isRegular)
                                ledgerStreamSection(isRegular: isRegular)
                            } else {
                                emptyLedgerStateCard
                            }
                        }
                        .padding(.horizontal, horizontalMargin)
                        .padding(.top, 8)
                        .padding(.bottom, 60)
                    }
                    .refreshable {
                        viewModel.refreshCurrent()
                    }
                }

                if viewModel.showToast, let msg = viewModel.toastMessage {
                    floatingToastPill(msg)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                        .padding(.bottom, 24)
                }
            }
        }
        .environment(\.layoutDirection, Language.isRTL() ? .rightToLeft : .leftToRight)
    }

    // MARK: - Navigation Bar

    private var sovereignNavigationBar: some View {
        AdminSovereignNavigationBar(
            title: Language.get("Providers_Accounting_Title", alter: "دفتر العمولات المحاسبي"),
            subtitle: Language.get("Providers_Accounting_SecureLedger", alter: "READONLY_SERVER_LEDGER • سجل مالي خادم محصّن"),
            statusDotColor: Color(red: 0.08, green: 0.74, blue: 0.48),
            onBack: {
                if let onDismiss = onDismiss {
                    onDismiss()
                } else {
                    PPAdminNavigationFallback.popOrDismiss()
                }
            }
        ) {
            HStack(spacing: 8) {
                // Live Refresh Action Button
                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    viewModel.refreshCurrent()
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(AdminSurface.primary)
                        .rotationEffect(.degrees(viewModel.isRefreshing ? 360 : 0))
                        .animation(viewModel.isRefreshing ? Animation.linear(duration: 0.8).repeatForever(autoreverses: false) : .default, value: viewModel.isRefreshing)
                        .frame(width: 38, height: 38)
                        .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .strokeBorder(Color(uiColor: .ppSurfaceBorder).opacity(0.3), lineWidth: 0.5)
                        )
                }
                .accessibilityLabel(Language.get("DC_Refresh", alter: "تحديث"))

                // Export / Summary Copy Action
                if viewModel.summary != nil {
                    Button {
                        viewModel.copyExecutiveSummary()
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "doc.on.doc.fill")
                                .font(.system(size: 12, weight: .bold))
                            Text(Language.get("Export", alter: "تصدير"))
                                .font(AdminType.captionBold)
                        }
                        .foregroundColor(AdminSurface.primary)
                        .padding(.horizontal, 10)
                        .frame(height: 38)
                        .background(AdminSurface.primary.opacity(0.10), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                }

                // Switch / Change Provider Quick Button
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                        viewModel.isChangingProvider.toggle()
                    }
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: viewModel.isChangingProvider ? "xmark" : "building.2.crop.circle")
                            .font(.system(size: 13, weight: .semibold))
                        Text(viewModel.isChangingProvider ? Language.get("Close", alter: "إغلاق") : Language.get("Switch", alter: "تغيير"))
                            .font(AdminType.captionBold)
                    }
                    .foregroundColor(AdminSurface.primaryText)
                    .padding(.horizontal, 10)
                    .frame(height: 38)
                    .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(Color(uiColor: .ppSurfaceBorder).opacity(0.3), lineWidth: 0.5)
                    )
                }
            }
        }
    }

    private var embeddedTabBar: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(Language.get("Providers_Accounting_Title", alter: "دفتر العمولات المحاسبي"))
                    .font(AdminType.title3)
                    .foregroundColor(AdminSurface.primaryText)
                HStack(spacing: 4) {
                    Circle()
                        .fill(Color(red: 0.08, green: 0.74, blue: 0.48))
                        .frame(width: 6, height: 6)
                    Text(Language.get("Providers_Accounting_SecureLedger", alter: "READONLY_SERVER_LEDGER"))
                        .font(AdminType.caption2)
                        .foregroundColor(AdminSurface.secondaryText)
                }
            }
            Spacer()
            HStack(spacing: 8) {
                // Live Refresh Action Button
                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    viewModel.refreshCurrent()
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(AdminSurface.primary)
                        .rotationEffect(.degrees(viewModel.isRefreshing ? 360 : 0))
                        .animation(viewModel.isRefreshing ? Animation.linear(duration: 0.8).repeatForever(autoreverses: false) : .default, value: viewModel.isRefreshing)
                        .frame(width: 36, height: 36)
                        .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .strokeBorder(Color(uiColor: .ppSurfaceBorder).opacity(0.3), lineWidth: 0.5)
                        )
                }
                .accessibilityLabel(Language.get("DC_Refresh", alter: "تحديث"))

                if viewModel.summary != nil {
                    Button {
                        viewModel.copyExecutiveSummary()
                    } label: {
                        Image(systemName: "doc.on.doc.fill")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(AdminSurface.primary)
                            .frame(width: 36, height: 36)
                            .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .strokeBorder(Color(uiColor: .ppSurfaceBorder).opacity(0.3), lineWidth: 0.5)
                            )
                    }
                    .accessibilityLabel(Language.get("Export", alter: "تصدير"))
                }

                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                        viewModel.isChangingProvider.toggle()
                    }
                } label: {
                    Image(systemName: viewModel.isChangingProvider ? "xmark" : "building.2.crop.circle")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(AdminSurface.primaryText)
                        .frame(width: 36, height: 36)
                        .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .strokeBorder(Color(uiColor: .ppSurfaceBorder).opacity(0.3), lineWidth: 0.5)
                        )
                }
                .accessibilityLabel(Language.get("Switch", alter: "تغيير المزود"))
            }
        }
        .padding(.horizontal, AdminSpacing.screenMargin)
        .padding(.vertical, 8)
    }

    // MARK: - Provider Radar & Identity Omnibar

    private var providerRadarCapsule: some View {
        VStack(spacing: 12) {
            if !viewModel.isChangingProvider, let identity = viewModel.currentIdentity {
                // Collapsed Identity Capsule
                HStack(spacing: 12) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(AdminSurface.primary.opacity(0.12))
                            .frame(width: 44, height: 44)
                        Image(systemName: "building.2.fill")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(AdminSurface.primary)
                    }

                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 6) {
                            Text(identity.name)
                                .font(AdminType.headline)
                                .foregroundColor(AdminSurface.primaryText)
                                .lineLimit(1)
                            Image(systemName: "checkmark.seal.fill")
                                .font(.system(size: 13))
                                .foregroundColor(Color(red: 0.08, green: 0.74, blue: 0.48))
                        }

                        HStack(spacing: 8) {
                            Text(identity.id)
                                .font(.system(size: 12, weight: .medium, design: .monospaced))
                                .foregroundColor(AdminSurface.secondaryText)
                                .lineLimit(1)

                            Button {
                                UIPasteboard.general.string = identity.id
                                viewModel.triggerToast(Language.get("Copied_To_Clipboard", alter: "تم نسخ معرّف المزود"))
                            } label: {
                                Image(systemName: "doc.on.doc")
                                    .font(.system(size: 10))
                                    .foregroundColor(AdminSurface.primary)
                            }

                            Text("•")
                                .font(.caption)
                                .foregroundColor(AdminSurface.secondaryText.opacity(0.5))

                            Text(Language.get("Active", alter: "نشط ومعتمد"))
                                .font(AdminType.caption2)
                                .foregroundColor(Color(red: 0.08, green: 0.74, blue: 0.48))
                        }
                    }

                    Spacer()

                    Button {
                        UISelectionFeedbackGenerator().selectionChanged()
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                            viewModel.isChangingProvider = true
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Text(Language.get("Switch", alter: "تغيير"))
                                .font(AdminType.captionBold)
                            Image(systemName: "arrow.triangle.2.circlepath")
                                .font(.system(size: 11, weight: .bold))
                        }
                        .foregroundColor(AdminSurface.primary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(AdminSurface.primary.opacity(0.10), in: Capsule())
                    }
                }
                .padding(AdminSpacing.cardPadding)
                .background(
                    RoundedRectangle(cornerRadius: AdminRadius.card, style: .continuous)
                        .fill(AdminSurface.surface)
                        .shadow(color: Color.black.opacity(0.03), radius: 8, x: 0, y: 3)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: AdminRadius.card, style: .continuous)
                        .strokeBorder(Color(uiColor: .ppSurfaceBorder).opacity(0.35), lineWidth: 0.75)
                )
            } else {
                // Expanded Omnibar Search & Quick Select Rail
                VStack(spacing: 12) {
                    HStack(spacing: 10) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundColor(AdminSurface.secondaryText)

                        TextField(Language.get("Providers_Accounting_ProviderPlaceholder", alter: "أدخل معرّف المزود المصرح به…"), text: $viewModel.inputProviderID)
                            .font(AdminType.body)
                            .foregroundColor(AdminSurface.primaryText)
                            .autocapitalization(.none)
                            .disableAutocorrection(true)
                            .onSubmit {
                                viewModel.loadReport(for: viewModel.inputProviderID)
                            }

                        if !viewModel.inputProviderID.isEmpty {
                            Button {
                                viewModel.inputProviderID = ""
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: 14))
                                    .foregroundColor(AdminSurface.secondaryText)
                            }
                        }

                        if let clip = UIPasteboard.general.string, !clip.isEmpty, viewModel.inputProviderID.isEmpty {
                            Button {
                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                viewModel.inputProviderID = clip.trimmingCharacters(in: .whitespacesAndNewlines)
                            } label: {
                                HStack(spacing: 3) {
                                    Image(systemName: "doc.on.clipboard")
                                        .font(.system(size: 11))
                                    Text(Language.get("Paste", alter: "لصق"))
                                        .font(AdminType.caption2Bold)
                                }
                                .foregroundColor(AdminSurface.primary)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(AdminSurface.primary.opacity(0.10), in: Capsule())
                            }
                        }

                        Button {
                            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                            viewModel.loadReport(for: viewModel.inputProviderID)
                        } label: {
                            HStack(spacing: 5) {
                                if viewModel.isLoading {
                                    ProgressView()
                                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                        .scaleEffect(0.7)
                                } else {
                                    Image(systemName: "arrow.down.doc.fill")
                                        .font(.system(size: 12, weight: .bold))
                                }
                                Text(Language.get("Providers_Accounting_LoadReport", alter: "تحميل التقرير"))
                                    .font(AdminType.captionBold)
                            }
                            .foregroundColor(.white)
                            .padding(.horizontal, 14)
                            .frame(height: 38)
                            .background(
                                RoundedRectangle(cornerRadius: 11, style: .continuous)
                                    .fill(AdminSurface.primary)
                                    .shadow(color: AdminSurface.primary.opacity(0.3), radius: 6, x: 0, y: 2)
                            )
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: AdminRadius.card, style: .continuous)
                            .fill(AdminSurface.surface)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: AdminRadius.card, style: .continuous)
                            .strokeBorder(Color(uiColor: .ppSurfaceBorder).opacity(0.4), lineWidth: 0.75)
                    )

                    // Quick-Select Verified Providers Rail
                    if !viewModel.verifiedProviders.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(Language.get("Providers_Verified_QuickSelect", alter: "المزودون المعتمدون"))
                                .font(AdminType.caption2Bold)
                                .foregroundColor(AdminSurface.secondaryText)
                                .padding(.horizontal, 4)

                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 8) {
                                    ForEach(viewModel.verifiedProviders) { provider in
                                        let isSelected = viewModel.currentProviderID == provider.id
                                        Button {
                                            UISelectionFeedbackGenerator().selectionChanged()
                                            viewModel.loadReport(for: provider.id)
                                        } label: {
                                            HStack(spacing: 6) {
                                                Circle()
                                                    .fill(isSelected ? Color.white : AdminSurface.primary)
                                                    .frame(width: 6, height: 6)
                                                Text(provider.name)
                                                    .font(AdminType.captionBold)
                                                Text(provider.id)
                                                    .font(.system(size: 10, design: .monospaced))
                                                    .opacity(0.7)
                                            }
                                            .foregroundColor(isSelected ? .white : AdminSurface.primaryText)
                                            .padding(.horizontal, 12)
                                            .padding(.vertical, 8)
                                            .background(
                                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                                    .fill(isSelected ? AdminSurface.primary : AdminSurface.control)
                                            )
                                            .overlay(
                                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                                    .strokeBorder(Color(uiColor: .ppSurfaceBorder).opacity(isSelected ? 0 : 0.4), lineWidth: 0.5)
                                            )
                                        }
                                    }
                                }
                                .padding(.horizontal, 2)
                                .padding(.vertical, 2)
                            }
                        }
                    }

                    // Recents Chips
                    if !viewModel.recentProviderIDs.isEmpty {
                        HStack(spacing: 6) {
                            Text(Language.get("Recent", alter: "المشاهدة مؤخراً:"))
                                .font(AdminType.caption2)
                                .foregroundColor(AdminSurface.secondaryText)

                            ForEach(viewModel.recentProviderIDs.prefix(3), id: \.self) { recentID in
                                Button {
                                    viewModel.loadReport(for: recentID)
                                } label: {
                                    Text(recentID)
                                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                                        .foregroundColor(AdminSurface.primary)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 4)
                                        .background(AdminSurface.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                                }
                            }
                            Spacer()
                        }
                        .padding(.horizontal, 4)
                    }
                }
                .padding(AdminSpacing.cardPadding)
                .background(
                    RoundedRectangle(cornerRadius: AdminRadius.card, style: .continuous)
                        .fill(AdminSurface.surface)
                        .shadow(color: Color.black.opacity(0.03), radius: 8, x: 0, y: 3)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: AdminRadius.card, style: .continuous)
                        .strokeBorder(Color(uiColor: .ppSurfaceBorder).opacity(0.35), lineWidth: 0.75)
                )
            }
        }
    }

    // MARK: - Apex Financial Telemetry Hero

    private func apexTelemetryHero(summary: ProviderLedgerSummary, isRegular: Bool) -> some View {
        VStack(spacing: 16) {
            // Hero Title Strip
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Image(systemName: "lock.shield.fill")
                            .font(.system(size: 12))
                            .foregroundColor(Color(red: 0.08, green: 0.74, blue: 0.48))
                        Text(Language.get("Providers_Accounting_AuditedDeck", alter: "الأستاذ المالي الخادم • تدقيق غير قابل للتعديل"))
                            .font(AdminType.caption2Bold)
                            .foregroundColor(Color(red: 0.08, green: 0.74, blue: 0.48))
                    }

                    Text(Language.get("Providers_Accounting_HeroTitle", alter: "دفتر العمولات ومسارات التسوية"))
                        .font(AdminType.title2)
                        .foregroundColor(AdminSurface.primaryText)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 2) {
                    Text("\(summary.count)")
                        .font(.system(size: 22, weight: .heavy, design: .rounded))
                        .foregroundColor(AdminSurface.primary)
                    Text(Language.get("Entries", alter: "قيود مسجلة"))
                        .font(AdminType.caption2)
                        .foregroundColor(AdminSurface.secondaryText)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }

            // 3-Pillar Financial Glass Cards
            if isRegular {
                HStack(spacing: 12) {
                    grossVolumeCard(summary: summary)
                    providerNetCard(summary: summary)
                    platformCommissionCard(summary: summary)
                }
            } else {
                VStack(spacing: 10) {
                    HStack(spacing: 10) {
                        grossVolumeCard(summary: summary)
                        providerNetCard(summary: summary)
                    }
                    platformCommissionCard(summary: summary)
                }
            }

            // Financial Split Waterfall Bar
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(Language.get("Financial_Distribution", alter: "توزيع التدفق المالي"))
                        .font(AdminType.caption2Bold)
                        .foregroundColor(AdminSurface.secondaryText)
                    Spacer()
                    Text("\(String(format: "%.1f", summary.providerRatio * 100))% للمزود · \(String(format: "%.1f", summary.effectiveTakeRate))% للمنصة")
                        .font(AdminType.caption2)
                        .foregroundColor(AdminSurface.primaryText)
                }

                GeometryReader { barGeo in
                    let providerWidth = max(barGeo.size.width * CGFloat(summary.providerRatio), 12)
                    let platformWidth = max(barGeo.size.width - providerWidth, 12)

                    HStack(spacing: 2) {
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(Color(red: 0.08, green: 0.74, blue: 0.48))
                            .frame(width: providerWidth)

                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(AdminSurface.primary)
                            .frame(width: platformWidth)
                    }
                }
                .frame(height: 10)
                .clipShape(Capsule())
            }
            .padding(.horizontal, 4)

            // Settlement Status Stream Badges
            HStack(spacing: 10) {
                settlementPill(
                    title: Language.get("Settled_Balance", alter: "المسواة"),
                    amount: summary.settledBalance,
                    currency: summary.currency,
                    color: Color(red: 0.08, green: 0.74, blue: 0.48),
                    symbol: "checkmark.circle.fill"
                )

                settlementPill(
                    title: Language.get("Pending_Balance", alter: "قيد المعالجة"),
                    amount: summary.pendingBalance,
                    currency: summary.currency,
                    color: Color(red: 0.96, green: 0.62, blue: 0.14),
                    symbol: "clock.arrow.circlepath"
                )

                if summary.voidedSales > 0 {
                    settlementPill(
                        title: Language.get("Voided_Sales", alter: "الملغاة"),
                        amount: summary.voidedSales,
                        currency: summary.currency,
                        color: Color(red: 0.94, green: 0.28, blue: 0.34),
                        symbol: "xmark.circle.fill"
                    )
                }
            }
        }
        .padding(AdminSpacing.cardPadding)
        .background(
            RoundedRectangle(cornerRadius: AdminRadius.card, style: .continuous)
                .fill(AdminSurface.surface)
                .shadow(color: Color.black.opacity(0.04), radius: 10, x: 0, y: 4)
        )
        .overlay(
            RoundedRectangle(cornerRadius: AdminRadius.card, style: .continuous)
                .strokeBorder(Color(uiColor: .ppSurfaceBorder).opacity(0.35), lineWidth: 0.75)
        )
    }

    private func grossVolumeCard(summary: ProviderLedgerSummary) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(Language.get("Gross_Volume", alter: "إجمالي المبيعات"))
                    .font(AdminType.caption2Bold)
                    .foregroundColor(AdminSurface.secondaryText)
                Spacer()
                Image(systemName: "chart.line.uptrend.xyaxis")
                    .font(.system(size: 12))
                    .foregroundColor(AdminSurface.primary)
            }

            Text(viewModel.formatMoney(summary.totalSales, currency: summary.currency))
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundColor(AdminSurface.primaryText)
                .minimumScaleFactor(0.7)
                .lineLimit(1)

            Text(Language.get("Gross_Volume_Desc", alter: "حجم التداولات الكلي"))
                .font(.system(size: 10))
                .foregroundColor(AdminSurface.secondaryText.opacity(0.8))
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func providerNetCard(summary: ProviderLedgerSummary) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(Language.get("Provider_Net", alter: "صافي المزود"))
                    .font(AdminType.caption2Bold)
                    .foregroundColor(Color(red: 0.08, green: 0.74, blue: 0.48))
                Spacer()
                Image(systemName: "banknote.fill")
                    .font(.system(size: 12))
                    .foregroundColor(Color(red: 0.08, green: 0.74, blue: 0.48))
            }

            Text(viewModel.formatMoney(summary.providerNet, currency: summary.currency))
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundColor(Color(red: 0.08, green: 0.74, blue: 0.48))
                .minimumScaleFactor(0.7)
                .lineLimit(1)

            Text(Language.get("Provider_Net_Desc", alter: "مستحقات الشريك المعتمدة"))
                .font(.system(size: 10))
                .foregroundColor(Color(red: 0.08, green: 0.74, blue: 0.48).opacity(0.8))
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(red: 0.08, green: 0.74, blue: 0.48).opacity(0.08), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color(red: 0.08, green: 0.74, blue: 0.48).opacity(0.25), lineWidth: 0.75)
        )
    }

    private func platformCommissionCard(summary: ProviderLedgerSummary) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(Language.get("Platform_Share", alter: "عمولة المنصة"))
                    .font(AdminType.caption2Bold)
                    .foregroundColor(AdminSurface.primary)
                Spacer()
                HStack(spacing: 3) {
                    Image(systemName: "percent")
                        .font(.system(size: 9, weight: .bold))
                    Text(String(format: "%.1f%%", summary.effectiveTakeRate))
                        .font(.system(size: 10, weight: .bold))
                }
                .foregroundColor(AdminSurface.primary)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(AdminSurface.primary.opacity(0.12), in: Capsule())
            }

            Text(viewModel.formatMoney(summary.platformShare, currency: summary.currency))
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundColor(AdminSurface.primary)
                .minimumScaleFactor(0.7)
                .lineLimit(1)

            Text(Language.get("Platform_Share_Desc", alter: "إيرادات الرسوم المقتطعة"))
                .font(.system(size: 10))
                .foregroundColor(AdminSurface.primary.opacity(0.8))
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AdminSurface.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(AdminSurface.primary.opacity(0.20), lineWidth: 0.75)
        )
    }

    private func settlementPill(title: String, amount: Double, currency: String, color: Color, symbol: String) -> some View {
        HStack(spacing: 6) {
            Circle()
                .fill(color)
                .frame(width: 6, height: 6)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(AdminSurface.secondaryText)
                Text(viewModel.formatMoney(amount, currency: currency))
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundColor(color)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    // MARK: - Ledger Controls & Filter Strip

    private func ledgerControlsStrip(isRegular: Bool) -> some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                // In-Ledger Search Field
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 13))
                        .foregroundColor(AdminSurface.secondaryText)

                    TextField(Language.get("Search_In_Ledger", alter: "بحث برقم الطلب أو القيد…"), text: $viewModel.inLedgerSearchText)
                        .font(AdminType.caption1)
                        .foregroundColor(AdminSurface.primaryText)

                    if !viewModel.inLedgerSearchText.isEmpty {
                        Button {
                            viewModel.inLedgerSearchText = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 12))
                                .foregroundColor(AdminSurface.secondaryText)
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: 10, style: .continuous))

                // Sort Menu
                Menu {
                    ForEach(LedgerSortOption.allCases, id: \.self) { option in
                        Button {
                            viewModel.sortOption = option
                        } label: {
                            HStack {
                                Text(option.title)
                                if viewModel.sortOption == option {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.up.arrow.down")
                            .font(.system(size: 12, weight: .semibold))
                        Text(viewModel.sortOption.title)
                            .font(AdminType.caption2Bold)
                    }
                    .foregroundColor(AdminSurface.primaryText)
                    .padding(.horizontal, 10)
                    .frame(height: 36)
                    .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
            }

            // Status Filter Chips
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(LedgerStatusFilter.allCases, id: \.self) { filter in
                        let isSelected = viewModel.selectedFilter == filter
                        let count = countForFilter(filter)

                        Button {
                            UISelectionFeedbackGenerator().selectionChanged()
                            withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                                viewModel.selectedFilter = filter
                            }
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: filter.icon)
                                    .font(.system(size: 11, weight: isSelected ? .bold : .medium))

                                Text(filter.title)
                                    .font(isSelected ? AdminType.captionBold : AdminType.caption1)

                                Text("\(count)")
                                    .font(.system(size: 11, weight: .bold, design: .rounded))
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(
                                        isSelected
                                            ? Color.white.opacity(0.25)
                                            : Color(uiColor: .ppSurfaceBorder).opacity(0.35),
                                        in: Capsule()
                                    )
                            }
                            .foregroundColor(isSelected ? .white : AdminSurface.primaryText)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .background(
                                isSelected
                                    ? AnyView(
                                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                                            .fill(filter.color)
                                            .shadow(color: filter.color.opacity(0.3), radius: 4, x: 0, y: 2)
                                    )
                                    : AnyView(
                                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                                            .fill(AdminSurface.control)
                                    )
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .strokeBorder(Color(uiColor: .ppSurfaceBorder).opacity(isSelected ? 0 : 0.35), lineWidth: 0.5)
                            )
                        }
                    }
                }
                .padding(.horizontal, 2)
                .padding(.vertical, 2)
            }
        }
    }

    private func countForFilter(_ filter: LedgerStatusFilter) -> Int {
        switch filter {
        case .all: return viewModel.records.count
        case .settled: return viewModel.records.filter { $0.status.lowercased() == "settled" }.count
        case .pending: return viewModel.records.filter { $0.status.lowercased() == "pending" }.count
        case .voided: return viewModel.records.filter { $0.status.lowercased() == "voided" }.count
        }
    }

    // MARK: - Ledger Stream Section

    private func ledgerStreamSection(isRegular: Bool) -> some View {
        let items = viewModel.filteredRecords

        return VStack(spacing: 12) {
            if items.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "doc.text.magnifyingglass")
                        .font(.system(size: 32))
                        .foregroundColor(AdminSurface.secondaryText.opacity(0.5))
                    Text(Language.get("No_Matching_Records", alter: "لا توجد قيود تطابق الفلتر الحالي"))
                        .font(AdminType.body)
                        .foregroundColor(AdminSurface.primaryText)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 40)
                .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: AdminRadius.card, style: .continuous))
            } else {
                if isRegular {
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                        ForEach(items) { record in
                            auditedLedgerCard(record: record)
                        }
                    }
                } else {
                    LazyVStack(spacing: 12) {
                        ForEach(items) { record in
                            auditedLedgerCard(record: record)
                        }
                    }
                }
            }
        }
    }

    private func auditedLedgerCard(record: PPProviderCommissionRecord) -> some View {
        let isExpanded = viewModel.expandedRecordIDs.contains(record.recordID)
        let statusColor = statusColorFor(record.status)
        let statusTitle = statusTitleFor(record.status)

        return VStack(spacing: 0) {
            // Card Header
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Image(systemName: "cart.fill")
                            .font(.system(size: 11))
                            .foregroundColor(AdminSurface.primary)

                        Text(record.orderID.isEmpty ? record.recordID : "#\(record.orderID)")
                            .font(.system(size: 14, weight: .bold, design: .monospaced))
                            .foregroundColor(AdminSurface.primaryText)

                        Button {
                            UIPasteboard.general.string = record.orderID.isEmpty ? record.recordID : record.orderID
                            viewModel.triggerToast(Language.get("Copied_To_Clipboard", alter: "تم نسخ معرّف الطلب"))
                        } label: {
                            Image(systemName: "doc.on.doc")
                                .font(.system(size: 10))
                                .foregroundColor(AdminSurface.secondaryText)
                        }
                    }

                    Text(viewModel.formatDate(record.createdAt))
                        .font(.system(size: 11))
                        .foregroundColor(AdminSurface.secondaryText)
                }

                Spacer()

                // Status Badge
                HStack(spacing: 4) {
                    Circle()
                        .fill(statusColor)
                        .frame(width: 6, height: 6)
                    Text(statusTitle)
                        .font(AdminType.caption2Bold)
                        .foregroundColor(statusColor)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(statusColor.opacity(0.12), in: Capsule())
                .overlay(
                    Capsule().strokeBorder(statusColor.opacity(0.3), lineWidth: 0.5)
                )
            }
            .padding(.horizontal, 14)
            .padding(.top, 14)
            .padding(.bottom, 10)

            Divider()
                .background(Color(uiColor: .ppSurfaceBorder).opacity(0.3))

            // Financial Waterfall Metrics
            HStack(spacing: 8) {
                // Gross Sale
                VStack(alignment: .leading, spacing: 2) {
                    Text(Language.get("Gross", alter: "الإجمالي"))
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(AdminSurface.secondaryText)
                    Text(viewModel.formatMoney(record.grossSaleAmount, currency: record.currency))
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundColor(AdminSurface.primaryText)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                // Platform Cut
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 2) {
                        Text(Language.get("Commission", alter: "العمولة"))
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(AdminSurface.primary)
                        Text("(\(String(format: "%.0f", record.commissionRate * 100))%)")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(AdminSurface.primary)
                    }
                    Text(viewModel.formatMoney(record.platformCommissionAmount, currency: record.currency))
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundColor(AdminSurface.primary)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                // Provider Net
                VStack(alignment: .leading, spacing: 2) {
                    Text(Language.get("Net", alter: "الصافي"))
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(Color(red: 0.08, green: 0.74, blue: 0.48))
                    Text(viewModel.formatMoney(record.providerNetAmount, currency: record.currency))
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundColor(Color(red: 0.08, green: 0.74, blue: 0.48))
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(AdminSurface.control.opacity(0.5))

            // Expandable Audit Drawer
            if isExpanded {
                VStack(alignment: .leading, spacing: 8) {
                    Divider()
                        .background(Color(uiColor: .ppSurfaceBorder).opacity(0.3))

                    VStack(alignment: .leading, spacing: 6) {
                        auditInfoRow(
                            label: Language.get("Ledger_Record_ID", alter: "قيد الأستاذ:"),
                            value: record.recordID
                        )

                        if !record.fulfillmentID.isEmpty {
                            auditInfoRow(
                                label: Language.get("Fulfillment_ID", alter: "رمز التجهيز:"),
                                value: record.fulfillmentID
                            )
                        }

                        auditInfoRow(
                            label: Language.get("Rate", alter: "نسبة الاقتطاع:"),
                            value: String(format: "%.2f%%", record.commissionRate * 100)
                        )
                    }
                    .padding(.horizontal, 14)
                    .padding(.top, 4)

                    // Action Button inside Drawer
                    Button {
                        viewModel.copyRecordSummary(record)
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "doc.on.doc.fill")
                                .font(.system(size: 11))
                            Text(Language.get("Copy_Audit_Evidence", alter: "نسخ بطاقة الإثبات المحاسبي"))
                                .font(AdminType.caption2Bold)
                        }
                        .foregroundColor(AdminSurface.primary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(AdminSurface.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
                    .padding(.horizontal, 14)
                    .padding(.bottom, 10)
                }
            }

            // Expansion Handle
            Button {
                viewModel.toggleExpansion(for: record.recordID)
            } label: {
                HStack(spacing: 4) {
                    Text(isExpanded ? Language.get("Less_Details", alter: "إخفاء التفاصيل") : Language.get("More_Details", alter: "تفاصيل القيد الخادم"))
                        .font(AdminType.caption2)
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 9, weight: .bold))
                }
                .foregroundColor(AdminSurface.secondaryText)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 7)
                .background(AdminSurface.surface)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(AdminSurface.surface)
                .shadow(color: Color.black.opacity(0.02), radius: 6, x: 0, y: 2)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color(uiColor: .ppSurfaceBorder).opacity(0.35), lineWidth: 0.75)
        )
    }

    private func auditInfoRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(AdminType.caption2)
                .foregroundColor(AdminSurface.secondaryText)
            Spacer()
            Text(value)
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundColor(AdminSurface.primaryText)
                .lineLimit(1)
        }
    }

    private func statusColorFor(_ status: String) -> Color {
        switch status.lowercased() {
        case "settled": return Color(red: 0.08, green: 0.74, blue: 0.48)
        case "pending": return Color(red: 0.96, green: 0.62, blue: 0.14)
        case "voided": return Color(red: 0.94, green: 0.28, blue: 0.34)
        default: return AdminSurface.secondaryText
        }
    }

    private func statusTitleFor(_ status: String) -> String {
        switch status.lowercased() {
        case "settled": return Language.get("Settled", alter: "مسواة")
        case "pending": return Language.get("Pending", alter: "قيد المعالجة")
        case "voided": return Language.get("Voided", alter: "ملغاة")
        default: return status
        }
    }

    // MARK: - States & Zero States

    private var zeroStateWelcomeHero: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(AdminSurface.primary.opacity(0.08))
                    .frame(width: 80, height: 80)
                Image(systemName: "shield.lefthalf.filled.badge.checkmark")
                    .font(.system(size: 38))
                    .foregroundColor(AdminSurface.primary)
            }
            .padding(.top, 16)

            VStack(spacing: 6) {
                Text(Language.get("Providers_Accounting_WelcomeTitle", alter: "مركز تدقيق العمولات والأستاذ المالي"))
                    .font(AdminType.title2)
                    .foregroundColor(AdminSurface.primaryText)
                    .multilineTextAlignment(.center)

                Text(Language.get("Providers_Accounting_WelcomeSubtitle", alter: "نظام مالي محصّن يوثّق جميع لقطات البيع، عمولات المنصة، وصافي المستحقات للمزودين بدقة غير قابلة للتعديل."))
                    .font(AdminType.caption1)
                    .foregroundColor(AdminSurface.secondaryText)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 20)
            }

            // 3 Pillar Highlights
            VStack(spacing: 10) {
                highlightBullet(
                    icon: "lock.shield.fill",
                    title: Language.get("Immutable_Ledger", alter: "لقطات بيع خادمة غير قابلة للتعديل"),
                    subtitle: Language.get("Immutable_Ledger_Desc", alter: "مسارات تدقيق ثابتة ومحصنة تضمن حقوق الشركاء والمنصة.")
                )

                highlightBullet(
                    icon: "chart.pie.fill",
                    title: Language.get("Instant_Split", alter: "احتساب آلي فوري للنسب والعمولات"),
                    subtitle: Language.get("Instant_Split_Desc", alter: "فرز فوري للمبيعات الإجمالية وحصص الشركاء فور إتمام الطلب.")
                )

                highlightBullet(
                    icon: "doc.plaintext.fill",
                    title: Language.get("Audit_Transparency", alter: "إثباتات محاسبية وبنكية متكاملة"),
                    subtitle: Language.get("Audit_Transparency_Desc", alter: "إمكانية تصدير ومطابقة الحركات مع كشوفات الحسابات.")
                )
            }
            .padding(.vertical, 8)

            if !viewModel.verifiedProviders.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Text(Language.get("Quick_Explore_Providers", alter: "اختر أحد المزودين للبدء فوراً:"))
                        .font(AdminType.captionBold)
                        .foregroundColor(AdminSurface.primaryText)

                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                        ForEach(viewModel.verifiedProviders.prefix(4)) { provider in
                            Button {
                                viewModel.loadReport(for: provider.id)
                            } label: {
                                HStack(spacing: 8) {
                                    Image(systemName: "building.2.fill")
                                        .font(.system(size: 12))
                                        .foregroundColor(AdminSurface.primary)
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(provider.name)
                                            .font(AdminType.captionBold)
                                            .foregroundColor(AdminSurface.primaryText)
                                            .lineLimit(1)
                                        Text(provider.id)
                                            .font(.system(size: 9, design: .monospaced))
                                            .foregroundColor(AdminSurface.secondaryText)
                                    }
                                }
                                .padding(10)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                            }
                        }
                    }
                }
                .padding(.horizontal, 8)
            }
        }
        .padding(AdminSpacing.cardPadding)
        .background(
            RoundedRectangle(cornerRadius: AdminRadius.card, style: .continuous)
                .fill(AdminSurface.surface)
                .shadow(color: Color.black.opacity(0.03), radius: 8, x: 0, y: 3)
        )
        .overlay(
            RoundedRectangle(cornerRadius: AdminRadius.card, style: .continuous)
                .strokeBorder(Color(uiColor: .ppSurfaceBorder).opacity(0.35), lineWidth: 0.75)
        )
    }

    private func highlightBullet(icon: String, title: String, subtitle: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundColor(AdminSurface.primary)
                .frame(width: 24, height: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(AdminType.subheadlineBold)
                    .foregroundColor(AdminSurface.primaryText)
                Text(subtitle)
                    .font(AdminType.caption2)
                    .foregroundColor(AdminSurface.secondaryText)
            }
            Spacer()
        }
        .padding(10)
        .background(AdminSurface.control.opacity(0.6), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private var emptyLedgerStateCard: some View {
        VStack(spacing: 12) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 40))
                .foregroundColor(AdminSurface.secondaryText.opacity(0.6))
            Text(Language.get("Providers_Accounting_Empty", alter: "لا توجد سجلات عمولات"))
                .font(AdminType.title3)
                .foregroundColor(AdminSurface.primaryText)
            Text(Language.get("Providers_Accounting_Empty_Subtitle", alter: "لم يتم العثور على قيود عمولة غير قابلة للتعديل لهذا المزود حتى الآن."))
                .font(AdminType.caption1)
                .foregroundColor(AdminSurface.secondaryText)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 20)
        }
        .padding(.vertical, 48)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: AdminRadius.card, style: .continuous)
                .fill(AdminSurface.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: AdminRadius.card, style: .continuous)
                .strokeBorder(Color(uiColor: .ppSurfaceBorder).opacity(0.35), lineWidth: 0.75)
        )
    }

    private func errorStateCard(message: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 34))
                .foregroundColor(Color(red: 0.94, green: 0.28, blue: 0.34))
            Text(Language.get("Providers_Accounting_LoadFailed", alter: "تعذر تحميل تقرير العمولات"))
                .font(AdminType.headline)
                .foregroundColor(AdminSurface.primaryText)
            Text(message)
                .font(AdminType.caption1)
                .foregroundColor(AdminSurface.secondaryText)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 20)

            Button {
                viewModel.refreshCurrent()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 12, weight: .bold))
                    Text(Language.get("Retry", alter: "إعادة المحاولة"))
                        .font(AdminType.captionBold)
                }
                .foregroundColor(.white)
                .padding(.horizontal, 20)
                .frame(height: 38)
                .background(AdminSurface.primary, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
        }
        .padding(.vertical, 32)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: AdminRadius.card, style: .continuous)
                .fill(AdminSurface.surface)
        )
    }

    private var shimmerLoadingSkeleton: some View {
        VStack(spacing: 14) {
            RoundedRectangle(cornerRadius: AdminRadius.card, style: .continuous)
                .fill(AdminSurface.control)
                .frame(height: 180)
                .overlay(
                    ProgressView()
                        .scaleEffect(1.2)
                )

            VStack(spacing: 10) {
                ForEach(0..<3) { _ in
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(AdminSurface.control)
                        .frame(height: 80)
                }
            }
        }
    }

    // MARK: - Toast Pill

    private func floatingToastPill(_ message: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(Color(red: 0.08, green: 0.74, blue: 0.48))
            Text(message)
                .font(AdminType.captionBold)
                .foregroundColor(.white)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(
            Capsule()
                .fill(Color.black.opacity(0.85))
                .shadow(color: Color.black.opacity(0.15), radius: 10, x: 0, y: 5)
        )
    }
}

// MARK: - Hosting Controller Bridges

@objc(AdminProviderAccountingHostingController)
public final class AdminProviderAccountingHostingController: UIViewController {
    private let initialProviderID: String?

    @objc public init(providerID: String? = nil) {
        self.initialProviderID = providerID
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .ppBackground

        let accountingView = AdminProviderAccountingView(
            initialProviderID: initialProviderID,
            isEmbeddedInTab: false,
            onDismiss: { [weak self] in
                if let nav = self?.navigationController, nav.viewControllers.count > 1 {
                    nav.popViewController(animated: true)
                } else {
                    self?.dismiss(animated: true)
                }
            }
        )

        let host = UIHostingController(rootView: accountingView)
        addChild(host)
        view.addSubview(host.view)
        host.view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            host.view.topAnchor.constraint(equalTo: view.topAnchor),
            host.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            host.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            host.view.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        ])
        host.didMove(toParent: self)
    }

    public override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.setNavigationBarHidden(true, animated: animated)
    }
}
