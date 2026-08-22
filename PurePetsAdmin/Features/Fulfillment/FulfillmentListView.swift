//
//  FulfillmentListView.swift
//  PurePetsAdmin
//
//  Pure SwiftUI fulfillment list with stage filters, operational pulse header,
//  fulfillment cards. Reuses PPFulfillmentService backend.
//

import SwiftUI

// MARK: - Sendable

extension PPFulfillmentRecord: @unchecked Sendable {}

// MARK: - Fulfillment Stage

enum FulfillmentListStage: String, CaseIterable, Identifiable {
    case all = "all"
    case pending = "pending"
    case accepted = "accepted"
    case processing = "processing"
    case ready = "ready_for_pickup"
    case inTransit = "in_transit"
    case completed = "completed"
    case cancelled = "cancelled"

    var id: String { rawValue }

    var titleKey: String {
        switch self {
        case .all: return "Fulfillment_Stage_All"
        case .pending: return "Fulfillment_Stage_Pending"
        case .accepted: return "Fulfillment_Stage_Accepted"
        case .processing: return "Fulfillment_Stage_Processing"
        case .ready: return "Fulfillment_Stage_Ready"
        case .inTransit: return "Fulfillment_Stage_InTransit"
        case .completed: return "Fulfillment_Stage_Completed"
        case .cancelled: return "Fulfillment_Stage_Cancelled"
        }
    }

    func matches(_ status: String?) -> Bool {
        if self == .all { return true }
        return status?.lowercased() == rawValue.lowercased()
    }
}

// MARK: - Fulfillment List ViewModel

@MainActor
final class FulfillmentListViewModel: ObservableObject {
    @Published private(set) var records: [PPFulfillmentRecord] = []
    @Published private(set) var isLoading = false
    @Published var errorMessage: String?
    @Published var selectedStage: FulfillmentListStage = .all
    @Published var searchText: String = ""

    private var listener: AnyObject?

    var filteredRecords: [PPFulfillmentRecord] {
        var result = records
        if selectedStage != .all {
            result = result.filter { selectedStage.matches($0.status) }
        }
        if !searchText.isEmpty {
            let q = searchText.lowercased()
            result = result.filter { record in
                (record.fulfillmentID ?? "").lowercased().contains(q) ||
                (record.customerName ?? "").lowercased().contains(q) ||
                (record.parentOrderNumber ?? "").lowercased().contains(q)
            }
        }
        return result
    }

    var operationalPulse: (pending: Int, active: Int, completed: Int) {
        let pending = records.filter { FulfillmentListStage.pending.matches($0.status) }.count
        let active = records.filter {
            FulfillmentListStage.accepted.matches($0.status) ||
            FulfillmentListStage.processing.matches($0.status) ||
            FulfillmentListStage.ready.matches($0.status) ||
            FulfillmentListStage.inTransit.matches($0.status)
        }.count
        let completed = records.filter { FulfillmentListStage.completed.matches($0.status) }.count
        return (pending, active, completed)
    }

    func startListening() {
        isLoading = true
        errorMessage = nil
        listener = PPFulfillmentService.shared().observeFulfillments { [weak self] records, _, error in
            Task { @MainActor in
                guard let self else { return }
                self.isLoading = false
                if let error {
                    self.errorMessage = error.localizedDescription
                    return
                }
                self.records = records ?? []
            }
        }
    }

    func stopListening() {
        if let reg = listener as? NSObjectProtocol {
            NotificationCenter.default.removeObserver(reg)
        }
        listener = nil
    }

    func count(for stage: FulfillmentListStage) -> Int {
        if stage == .all { return records.count }
        return records.filter { stage.matches($0.status) }.count
    }
}

// MARK: - Fulfillment List View

struct AdminFulfillmentListView: View {
    let session: AdminSession
    var onDismiss: (() -> Void)? = nil
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel = FulfillmentListViewModel()

    init(session: AdminSession, onDismiss: (() -> Void)? = nil) {
        self.session = session
        self.onDismiss = onDismiss
    }

    var body: some View {
        VStack(spacing: 0) {
            dossierHeaderView
            operationalPulseHeader
            stageFilterBar
            Divider().background(AdminSurface.hairline)

            if viewModel.isLoading && viewModel.records.isEmpty {
                Spacer()
                ProgressView().tint(AdminSurface.primary).scaleEffect(1.2)
                Spacer()
            } else if viewModel.filteredRecords.isEmpty {
                Spacer()
                AdminEmptyStateView(
                    symbol: "shippingbox.fill",
                    title: Language.get("Fulfillment_No_Orders", alter: "لا توجد طلبات تنفيذ"),
                    subtitle: Language.get("Fulfillment_No_Orders_Sub", alter: "لم يتم العثور على طلبات تنفيذ")
                )
                Spacer()
            } else if let error = viewModel.errorMessage {
                Spacer()
                AdminErrorBanner(message: error, retry: { viewModel.startListening() })
                    .padding(.horizontal, AdminSpacing.screenMargin)
                Spacer()
            } else {
                fulfillmentList
            }
        }
        .background(AdminSurface.background)
        .environment(\.layoutDirection, Language.isRTL() ? .rightToLeft : .leftToRight)
        .onAppear { viewModel.startListening() }
        .onDisappear { viewModel.stopListening() }
    }

    // MARK: - Dossier Header (PPAccessoryEditorView Pattern)

    private var dossierHeaderView: some View {
        VStack(alignment: .leading, spacing: AdminSpacing.xs) {
            HStack {
                Button(action: {
                    if let onDismiss {
                        onDismiss()
                    } else {
                        dismiss()
                    }
                }) {
                    HStack(spacing: 6) {
                        Image(systemName: Language.isRTL() ? "chevron.right" : "chevron.left")
                            .font(.system(size: 16, weight: .semibold))
                        Text(Language.get("Back", alter: "رجوع"))
                            .font(AdminType.calloutBold)
                    }
                    .foregroundColor(AdminSurface.primary)
                    .frame(minHeight: 44)
                }

                Spacer()

                if viewModel.isLoading {
                    ProgressView().tint(AdminSurface.primary)
                } else {
                    Button(action: {
                        viewModel.stopListening()
                        viewModel.startListening()
                    }) {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(AdminSurface.primary)
                            .frame(width: 36, height: 36)
                            .background(AdminSurface.primary.opacity(0.10), in: Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Language.get("Refresh", alter: "تحديث"))
                }
            }

            Text(Language.get("CommandCenter_Fulfillment_Workspace", alter: "مساحة التنفيذ") + " / " + Language.get("Fulfillment_Title", alter: "إدارة طلبات التنفيذ"))
                .font(AdminType.caption1)
                .foregroundColor(AdminSurface.secondaryText)
                .padding(.top, 2)

            Text(Language.get("Fulfillment_Title", alter: "إدارة طلبات التنفيذ"))
                .font(AdminType.title2)
                .foregroundColor(AdminSurface.primaryText)

            if let error = viewModel.errorMessage {
                AdminErrorBanner(message: error, retry: { viewModel.startListening() })
                    .padding(.top, 4)
            }
        }
        .padding(.horizontal, AdminSpacing.screenMargin)
        .padding(.top, AdminSpacing.xs)
    }

    private var operationalPulseHeader: some View {
        let pulse = viewModel.operationalPulse
        return HStack(spacing: AdminSpacing.md) {
            PulseMetric(
                label: Language.get("Fulfillment_Pending", alter: "\u{0645}\u{0639}\u{0644}\u{0642}"),
                value: "\(pulse.pending)",
                color: .orange,
                symbol: "clock.fill"
            )
            PulseMetric(
                label: Language.get("Fulfillment_Active", alter: "\u{0646}\u{0634}\u{0637}"),
                value: "\(pulse.active)",
                color: AdminSurface.primary,
                symbol: "arrow.triangle.2.circlepath"
            )
            PulseMetric(
                label: Language.get("Fulfillment_Completed", alter: "\u{0645}\u{0643}\u{062a}\u{0645}\u{0644}"),
                value: "\(pulse.completed)",
                color: .green,
                symbol: "checkmark.circle.fill"
            )
        }
        .padding(.horizontal, AdminSpacing.screenMargin)
        .padding(.vertical, AdminSpacing.md)
    }

    private var stageFilterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: AdminSpacing.sm) {
                ForEach(FulfillmentListStage.allCases) { stage in
                    StageChip(
                        title: Language.get(stage.titleKey, alter: stage.rawValue),
                        count: viewModel.count(for: stage),
                        isSelected: viewModel.selectedStage == stage
                    ) {
                        viewModel.selectedStage = stage
                    }
                }
            }
            .padding(.horizontal, AdminSpacing.screenMargin)
        }
        .padding(.vertical, AdminSpacing.sm)
    }

    private var fulfillmentList: some View {
        ScrollView {
            LazyVStack(spacing: AdminSpacing.sm) {
                ForEach(viewModel.filteredRecords, id: \.fulfillmentID) { record in
                    FulfillmentCard(record: record)
                }
            }
            .padding(.horizontal, AdminSpacing.screenMargin)
            .padding(.vertical, AdminSpacing.sm)
        }
        .refreshable {
            viewModel.stopListening()
            viewModel.startListening()
            try? await Task.sleep(nanoseconds: 300_000_000)
        }
    }
}

// MARK: - Subviews

private struct PulseMetric: View {
    let label: String
    let value: String
    let color: Color
    let symbol: String

    var body: some View {
        HStack(spacing: AdminSpacing.sm) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(color)
                .frame(width: 32, height: 32)
                .background(color.opacity(0.10), in: RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 2) {
                Text(value)
                    .font(AdminType.headline)
                    .foregroundColor(AdminSurface.primaryText)
                    .monospacedDigit()
                Text(label)
                    .font(AdminType.caption2)
                    .foregroundColor(AdminSurface.secondaryText)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(AdminSpacing.md)
        .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: AdminRadius.card))
        .overlay(RoundedRectangle(cornerRadius: AdminRadius.card).stroke(AdminSurface.hairline))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label): \(value)")
    }
}

private struct StageChip: View {
    let title: String
    let count: Int
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Text(title)
                    .font(AdminType.captionBold)
                Text("\(count)")
                    .font(AdminType.caption2Bold)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(
                        isSelected ? Color.white.opacity(0.25) : AdminSurface.secondaryText.opacity(0.12),
                        in: Capsule()
                    )
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(isSelected ? AdminSurface.primary : AdminSurface.control, in: Capsule())
            .foregroundColor(isSelected ? .white : AdminSurface.secondaryText)
            .overlay(
                Capsule().stroke(isSelected ? Color.clear : AdminSurface.hairline, lineWidth: 1)
            )
        }
        .frame(minHeight: AdminTouchTarget.minimum)
        .accessibilityLabel("\(title): \(count)")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

private struct FulfillmentCard: View {
    let record: PPFulfillmentRecord

    var body: some View {
        VStack(spacing: AdminSpacing.sm) {
            HStack {
                Text(record.parentOrderNumber ?? record.fulfillmentID ?? "-")
                    .font(AdminType.headline)
                    .foregroundColor(AdminSurface.primaryText)
                Spacer()
                AdminStatusBadge(
                    text: displayStatus,
                    status: badgeStatus
                )
            }

            HStack {
                Label(
                    record.customerName ?? "-",
                    systemImage: "person.fill"
                )
                .font(AdminType.captionBold)
                .foregroundColor(AdminSurface.secondaryText)
                Spacer()
                if let items = record.items as? [[String: Any]] {
                    Text("\(items.count) \(Language.get("Fulfillment_Items", alter: "\u{0639}\u{0646}\u{0627}\u{0635}\u{0631}"))")
                        .font(AdminType.caption2)
                        .foregroundColor(AdminSurface.secondaryText)
                }
            }
        }
        .padding(AdminSpacing.base)
        .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: AdminRadius.card))
        .overlay(RoundedRectangle(cornerRadius: AdminRadius.card).stroke(AdminSurface.hairline))
        .accessibilityElement(children: .combine)
    }

    private var displayStatus: String {
        let key = record.status ?? ""
        switch key.lowercased() {
        case "pending": return Language.get("Fulfillment_Stage_Pending", alter: "Pending")
        case "accepted": return Language.get("Fulfillment_Stage_Accepted", alter: "Accepted")
        case "processing": return Language.get("Fulfillment_Stage_Processing", alter: "Processing")
        case "ready_for_pickup": return Language.get("Fulfillment_Stage_Ready", alter: "Ready")
        case "in_transit": return Language.get("Fulfillment_Stage_InTransit", alter: "In Transit")
        case "completed": return Language.get("Fulfillment_Stage_Completed", alter: "Completed")
        case "cancelled": return Language.get("Fulfillment_Stage_Cancelled", alter: "Cancelled")
        default: return key.capitalized
        }
    }

    private var badgeStatus: AdminStatusBadge.Status {
        switch (record.status ?? "").lowercased() {
        case "completed": return .success
        case "cancelled": return .error
        case "pending": return .warning
        case "processing", "accepted", "ready_for_pickup", "in_transit": return .processing
        default: return .neutral
        }
    }
}
