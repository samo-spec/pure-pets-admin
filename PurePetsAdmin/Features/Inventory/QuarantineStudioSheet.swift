//
//  QuarantineStudioSheet.swift
//  PurePetsAdmin
//
//  Next-Gen Category-Defining Inspection & Disposition Studio
//  Bespoke architectures for iPhone (tactile mobile deck) & iPad (dual-pane command cockpit).
//  Governs 5-bucket inventory routing, financial impact telemetry, and audit-grade safety.
//

import SwiftUI
import UIKit
import AudioToolbox
import FirebaseFirestore
import FirebaseFunctions

// MARK: - Color Palette Extensions

private extension Color {
    static let emerald = Color(uiColor: .ppSuccess)
    static let violet = Color(red: 0.58, green: 0.35, blue: 0.95)
    static let amber = Color(uiColor: .ppWarning)
    static let crimson = Color(uiColor: .ppError)
    static let sapphire = Color(red: 0.15, green: 0.55, blue: 0.95)
}

// MARK: - Quarantine Studio Sheet (Root Container)

public struct QuarantineStudioSheet: View {
    public let item: PetAccessory
    public let branchId: String
    public var onResolved: (() -> Void)? = nil

    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @StateObject private var inventoryService = PPBranchInventoryService.shared

    // Source Bucket State
    @State private var sourceBucket: String = "quarantine"
    @State private var quantity: Int = 1

    // Action State
    @State private var selectedActionType: ActionType = .releaseToStock
    @State private var selectedReasonCode: String = "inspection_passed"
    @State private var notes: String = ""

    // Linked Disposition State (e.g. from POS return)
    @State private var pendingDispositions: [[String: Any]] = []
    @State private var selectedDispositionId: String? = nil
    @State private var isLoadingDispositions: Bool = false

    // Precision Numeric Keypad Modal State
    @State private var showingKeypadModal: Bool = false

    // Submission & Dialog State
    @State private var isSubmitting: Bool = false
    @State private var errorMessage: String? = nil

    public enum ActionType: String, CaseIterable, Identifiable {
        case releaseToStock = "release"
        case confirmDamaged = "damaged"
        case confirmExpired = "expired"
        case sendToQuarantine = "quarantine"
        case returnToSupplier = "supplier_return"
        case physicalWriteOff = "write_off"

        public var id: String { rawValue }

        public var isWriteOff: Bool {
            self == .physicalWriteOff
        }

        public var destinationBucket: String? {
            switch self {
            case .releaseToStock: return "available"
            case .confirmDamaged: return "damaged"
            case .confirmExpired: return "expired"
            case .sendToQuarantine: return "quarantine"
            case .returnToSupplier: return "supplierReturn"
            case .physicalWriteOff: return nil
            }
        }

        public var title: String {
            switch self {
            case .releaseToStock:
                return Language.get("Quarantine_Action_Release", alter: "إفراج للمخزون (صالح للبيع)")
            case .confirmDamaged:
                return Language.get("Quarantine_Action_Damage", alter: "تأكيد التلف")
            case .confirmExpired:
                return Language.get("Quarantine_Action_Expire", alter: "تأكيد انتهاء الصلاحية")
            case .sendToQuarantine:
                return Language.get("Quarantine_Action_ToQuarantine", alter: "نقل إلى حجر الفحص")
            case .returnToSupplier:
                return Language.get("Quarantine_Action_RTV", alter: "إرجاع للمورد (RTV)")
            case .physicalWriteOff:
                return Language.get("Quarantine_Action_WriteOff", alter: "إتلاف نهائي وشطب")
            }
        }

        public var subtitle: String {
            switch self {
            case .releaseToStock:
                return Language.get("Quarantine_Action_Release_Sub", alter: "إعادة إدخال الصنف للمخزون الجاهز للبيع (يتطلب تصريح إفراج)")
            case .confirmDamaged:
                return Language.get("Quarantine_Action_Damage_Sub", alter: "نقل إلى مخزون التوالف للفرز أو المطالبة")
            case .confirmExpired:
                return Language.get("Quarantine_Action_Expire_Sub", alter: "نقل إلى مخزون منتهي الصلاحية للشطب")
            case .sendToQuarantine:
                return Language.get("Quarantine_Action_ToQuarantine_Sub", alter: "إعادة البضاعة لحجر الفحص للمعاينة وإعادة التقييم قبل أي تصرف")
            case .returnToSupplier:
                return Language.get("Quarantine_Action_RTV_Sub", alter: "حجز للإرجاع واسترداد القيمة من المورد")
            case .physicalWriteOff:
                return Language.get("Quarantine_Action_WriteOff_Sub", alter: "شطب وإتلاف نهائي من العهدة الفعلية في الفرع")
            }
        }

        public var iconName: String {
            switch self {
            case .releaseToStock: return "checkmark.seal.fill"
            case .confirmDamaged: return "exclamationmark.triangle.fill"
            case .confirmExpired: return "clock.badge.xmark.fill"
            case .sendToQuarantine: return "shield.lefthalf.filled"
            case .returnToSupplier: return "arrow.uturn.backward.circle.fill"
            case .physicalWriteOff: return "trash.fill"
            }
        }

        public var accentColor: Color {
            switch self {
            case .releaseToStock: return .emerald
            case .confirmDamaged: return .amber
            case .confirmExpired: return .crimson
            case .sendToQuarantine: return .violet
            case .returnToSupplier: return .sapphire
            case .physicalWriteOff: return .violet
            }
        }
    }

    public init(item: PetAccessory, branchId: String, onResolved: (() -> Void)? = nil) {
        self.item = item
        self.branchId = branchId
        self.onResolved = onResolved
    }

    // MARK: - Computed Inventory Metrics

    private var branchRecord: PPBranchInventory? {
        inventoryService.inventory(for: item.accessoryID)
    }

    private var availableQty: Int {
        branchRecord?.availableQuantity ?? item.quantity
    }

    private var quarantineQty: Int {
        branchRecord?.quarantineQuantity ?? 0
    }

    private var damagedQty: Int {
        branchRecord?.damagedQuantity ?? 0
    }

    private var expiredQty: Int {
        branchRecord?.expiredQuantity ?? 0
    }

    private var supplierReturnQty: Int {
        branchRecord?.supplierReturnQuantity ?? 0
    }

    private var onHandQty: Int {
        branchRecord?.onHandQuantity ?? item.quantity
    }

    private var sourceAvailableCount: Int {
        switch sourceBucket {
        case "quarantine": return quarantineQty
        case "damaged": return damagedQty
        case "expired": return expiredQty
        case "supplierReturn": return supplierReturnQty
        case "available": return availableQty
        default: return 0
        }
    }

    private var sourceBucketTitle: String {
        switch sourceBucket {
        case "quarantine": return Language.get("Inventory_Quarantine", alter: "حجر الفحص")
        case "damaged": return Language.get("Inventory_Damaged", alter: "التوالف")
        case "expired": return Language.get("Inventory_Expired", alter: "المنتهي")
        case "supplierReturn": return Language.get("Inventory_Supplier_Return", alter: "مرتجع مورد")
        case "available": return Language.get("Inventory_Available", alter: "متوفر للبيع")
        default: return sourceBucket
        }
    }

    private var sourceBucketColor: Color {
        switch sourceBucket {
        case "quarantine": return .violet
        case "damaged": return .amber
        case "expired": return .crimson
        case "supplierReturn": return .sapphire
        case "available": return .emerald
        default: return .secondary
        }
    }

    private var canReleaseQuarantine: Bool {
        let staff = PPStaffAuth.shared().cachedCurrentStaff
        let isManager = staff?.hasPermission("stock.manage") ?? false
        let isQuarantineRelease = staff?.hasPermission("stock.quarantine.release") ?? false
        return isManager || isQuarantineRelease
    }

    private var resolvedBranchId: String {
        let trimmed = branchId.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty && trimmed != "all_branches" {
            return trimmed
        }
        if let active = BranchContextStore.shared.activeBranch?.branchID.trimmingCharacters(in: .whitespacesAndNewlines), !active.isEmpty {
            return active
        }
        let resolved = item.resolvedBranchID()
        return !resolved.isEmpty ? resolved : (item.storeID ?? "main_store")
    }

    private var allowedActionTypes: [ActionType] {
        switch sourceBucket {
        case "quarantine":
            return [.releaseToStock, .confirmDamaged, .confirmExpired, .returnToSupplier, .physicalWriteOff]
        case "damaged":
            return [.physicalWriteOff, .returnToSupplier, .sendToQuarantine]
        case "expired":
            return [.physicalWriteOff, .sendToQuarantine]
        case "supplierReturn":
            return [.returnToSupplier, .sendToQuarantine]
        case "available":
            return [.confirmDamaged, .confirmExpired, .sendToQuarantine]
        default:
            return [.physicalWriteOff, .sendToQuarantine]
        }
    }

    private var isSubmitDisabled: Bool {
        if isSubmitting { return true }
        if sourceAvailableCount <= 0 { return true }
        if quantity <= 0 || quantity > sourceAvailableCount { return true }
        if !allowedActionTypes.contains(selectedActionType) { return true }
        if selectedActionType == .releaseToStock && !canReleaseQuarantine { return true }
        return false
    }

    private var totalFinancialValue: Double {
        Double(quantity) * item.finalPrice.doubleValue
    }

    private var isPad: Bool {
        UIDevice.current.userInterfaceIdiom == .pad && horizontalSizeClass != .compact
    }

    // MARK: - Body

    public var body: some View {
        NavigationStack {
            ZStack {
                AdminSurface.background.ignoresSafeArea()

                VStack(spacing: 0) {
                    headerBar

                    if item.isLivePet {
                        LivePetVeterinaryQuarantineDeckView(
                            item: item,
                            branchId: resolvedBranchId,
                            branchRecord: branchRecord,
                            availableQty: availableQty,
                            quarantineQty: quarantineQty,
                            onDismiss: { dismiss() },
                            onResolved: {
                                onResolved?()
                                dismiss()
                            }
                        )
                    } else if isPad {
                        iPadInspectionCockpitView(
                            item: item,
                            branchRecord: branchRecord,
                            availableQty: availableQty,
                            quarantineQty: quarantineQty,
                            damagedQty: damagedQty,
                            expiredQty: expiredQty,
                            supplierReturnQty: supplierReturnQty,
                            onHandQty: onHandQty,
                            sourceBucket: $sourceBucket,
                            quantity: $quantity,
                            sourceAvailableCount: sourceAvailableCount,
                            sourceBucketTitle: sourceBucketTitle,
                            sourceBucketColor: sourceBucketColor,
                            selectedActionType: $selectedActionType,
                            selectedReasonCode: $selectedReasonCode,
                            notes: $notes,
                            applicableActions: allowedActionTypes,
                            applicableReasons: applicableReasonCodes,
                            pendingDispositions: pendingDispositions,
                            selectedDispositionId: $selectedDispositionId,
                            totalFinancialValue: totalFinancialValue,
                            canReleaseQuarantine: canReleaseQuarantine,
                            isSubmitDisabled: isSubmitDisabled,
                            isSubmitting: isSubmitting,
                            errorMessage: errorMessage,
                            onDismissError: { errorMessage = nil },
                            onOpenKeypad: { showingKeypadModal = true },
                            onSubmit: { promptPPAlertConfirmation() },
                            onSourceChanged: { normalizeReasonSelection() }
                        )
                    } else {
                        iPhoneInspectionDeckView(
                            item: item,
                            branchRecord: branchRecord,
                            availableQty: availableQty,
                            quarantineQty: quarantineQty,
                            damagedQty: damagedQty,
                            expiredQty: expiredQty,
                            supplierReturnQty: supplierReturnQty,
                            onHandQty: onHandQty,
                            sourceBucket: $sourceBucket,
                            quantity: $quantity,
                            sourceAvailableCount: sourceAvailableCount,
                            sourceBucketTitle: sourceBucketTitle,
                            sourceBucketColor: sourceBucketColor,
                            selectedActionType: $selectedActionType,
                            selectedReasonCode: $selectedReasonCode,
                            notes: $notes,
                            applicableActions: allowedActionTypes,
                            applicableReasons: applicableReasonCodes,
                            pendingDispositions: pendingDispositions,
                            selectedDispositionId: $selectedDispositionId,
                            totalFinancialValue: totalFinancialValue,
                            canReleaseQuarantine: canReleaseQuarantine,
                            isSubmitDisabled: isSubmitDisabled,
                            isSubmitting: isSubmitting,
                            errorMessage: errorMessage,
                            onDismissError: { errorMessage = nil },
                            onOpenKeypad: { showingKeypadModal = true },
                            onSubmit: { promptPPAlertConfirmation() },
                            onSourceChanged: { normalizeReasonSelection() }
                        )
                    }
                }
            }
            .navigationBarHidden(true)
            .environment(\.layoutDirection, Language.isRTL() ? .rightToLeft : .leftToRight)
            .onAppear {
                loadDispositions()
                normalizeInitialSelection()
            }
            .onChange(of: branchRecord) { _ in
                normalizeInitialSelection(force: false)
            }
            .sheet(isPresented: $showingKeypadModal) {
                QuarantinePrecisionKeypadModal(
                    maxQuantity: max(1, sourceAvailableCount),
                    initialQuantity: quantity,
                    onCommit: { newQty in
                        quantity = min(max(1, newQty), max(1, sourceAvailableCount))
                    }
                )
                .presentationDetents([.fraction(0.55), .medium])
                .presentationDragIndicator(.visible)
                .environment(\.layoutDirection, Language.isRTL() ? .rightToLeft : .leftToRight)
            }
        }
    }

    // MARK: - Header Bar

    private var headerBar: some View {
        ZStack {
            // Centered Screen Title with generous horizontal clearance
            Text(item.isLivePet ? Language.get("LivePet_Quarantine_Studio_Title", alter: "استوديو الحجر البيطري والعزل الطبي") : Language.get("Quarantine_Studio_Title", alter: "استوديو الفحص والتصرف"))
                .font(AdminType.headlineBold)
                .foregroundColor(AdminSurface.primaryText)
                .lineLimit(1)
                .padding(.horizontal, 60)

            // Cancellation Action Button
            HStack {
                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    dismiss()
                } label: {
                    Text(Language.get("Cancel", alter: "إلغاء"))
                        .font(AdminType.body)
                        .foregroundColor(AdminSurface.primary)
                }
                .keyboardShortcut(.cancelAction)

                Spacer()
            }
        }
        .padding(.horizontal, AdminSpacing.screenMargin)
        .padding(.top, 22)
        .padding(.bottom, 12)
        .frame(maxWidth: .infinity)
        .background(
            AdminSurface.background
                .ignoresSafeArea(edges: .top)
        )
        .overlay(
            Rectangle()
                .fill(AdminSurface.hairline.opacity(0.8))
                .frame(height: 0.5),
            alignment: .bottom
        )
        .zIndex(100)
    }

    // MARK: - Confirmation & Execution via PPAlertHelper

    private func promptPPAlertConfirmation() {
        let actionTitle = selectedActionType.title
        let valFormatted = String(format: "%.2f QAR", totalFinancialValue).normalizedEnglishDigits
        let confirmTitle = selectedActionType.isWriteOff
            ? Language.get("Quarantine_Confirm_Destruction", alter: "تأكيد الشطب والإتلاف")
            : Language.get("Confirm", alter: "تأكيد التنفيذ")
        let cancelTitle = Language.get("Cancel", alter: "إلغاء")

        let alertTitle = Language.get("Quarantine_Confirm_Title", alter: "تأكيد تنفيذ الإجراء")
        let alertSubtitle: String = {
            if selectedActionType.isWriteOff {
                return "\(Language.get("Quarantine_Warning_Writeoff", alter: "تحذير: سيتم شطب وإتلاف")): \(quantity) \(Language.get("Units", alter: "قطع")) بقيمة \(valFormatted) نهائياً من عهدة الفرع."
            } else {
                return "\(Language.get("Quarantine_Confirm_Summary", alter: "تأكيد توجيه")): \(quantity) \(Language.get("Units", alter: "قطع")) (\(valFormatted)) من [\(sourceBucketTitle)] إلى [\(actionTitle)]."
            }
        }()

        let icon = UIImage(systemName: selectedActionType.iconName)

        PPAlertHelper.showConfirmation(
            in: nil,
            title: alertTitle,
            subtitle: alertSubtitle,
            confirmButton: confirmTitle,
            cancelButton: cancelTitle,
            icon: icon,
            confirmBlock: { _, didConfirm in
                guard didConfirm else { return }
                executeDisposition()
            },
            cancelBlock: nil
        )
    }

    // MARK: - Logic & Handlers

    private func normalizeInitialSelection(force: Bool = false) {
        if !force && sourceAvailableCount > 0 {
            quantity = min(max(1, quantity), sourceAvailableCount)
            normalizeReasonSelection()
            return
        }

        if quarantineQty > 0 {
            sourceBucket = "quarantine"
            quantity = min(1, quarantineQty)
            selectedActionType = .releaseToStock
        } else if damagedQty > 0 {
            sourceBucket = "damaged"
            quantity = min(1, damagedQty)
            selectedActionType = .physicalWriteOff
        } else if expiredQty > 0 {
            sourceBucket = "expired"
            quantity = min(1, expiredQty)
            selectedActionType = .physicalWriteOff
        } else if supplierReturnQty > 0 {
            sourceBucket = "supplierReturn"
            quantity = min(1, supplierReturnQty)
            selectedActionType = .returnToSupplier
        } else if availableQty > 0 {
            // Can route from available to damaged/quarantine if damaged discovered on sales floor
            sourceBucket = "available"
            quantity = min(1, availableQty)
            selectedActionType = .confirmDamaged
        }
        normalizeReasonSelection()
    }

    private func normalizeReasonSelection() {
        if !allowedActionTypes.contains(selectedActionType) {
            selectedActionType = allowedActionTypes.first ?? .physicalWriteOff
        }
        if let first = applicableReasonCodes.first {
            selectedReasonCode = first.code
        }
    }

    private func loadDispositions() {
        isLoadingDispositions = true
        inventoryService.fetchDispositions(
            branchId: resolvedBranchId,
            status: "completed",
            limit: 20
        ) { result in
            isLoadingDispositions = false
            switch result {
            case .success(let items):
                let filtered = items.filter { ($0["productId"] as? String) == item.accessoryID }
                pendingDispositions = filtered
            case .failure:
                break
            }
        }
    }

    private func executeDisposition() {
        guard !isSubmitting else { return }
        isSubmitting = true
        errorMessage = nil

        let actionString = selectedActionType.isWriteOff ? "write_off" : "move"
        let destBucket = selectedActionType.destinationBucket

        inventoryService.resolveDisposition(
            productId: item.accessoryID,
            branchId: resolvedBranchId,
            quantity: quantity,
            action: actionString,
            fromBucket: sourceBucket,
            toBucket: destBucket,
            dispositionId: selectedDispositionId,
            reasonCode: selectedReasonCode,
            notes: notes
        ) { result in
            isSubmitting = false
            switch result {
            case .success:
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                onResolved?()
                dismiss()
            case .failure(let error):
                UINotificationFeedbackGenerator().notificationOccurred(.error)
                errorMessage = PPBranchInventoryErrorHelper.localizedMessage(for: error)
            }
        }
    }

    // MARK: - Applicable Reasons

    public struct ReasonEntry: Identifiable {
        public var id: String { code }
        public let code: String
        public let label: String
    }

    private var applicableReasonCodes: [ReasonEntry] {
        switch selectedActionType {
        case .releaseToStock:
            return [
                ReasonEntry(code: "inspection_passed", label: Language.get("Quarantine_Reason_Inspection_Passed", alter: "اجتياز الفحص المخبري/الظاهري")),
                ReasonEntry(code: "packaging_verified", label: Language.get("Quarantine_Reason_Packaging_OK", alter: "سلامة التغليف")),
                ReasonEntry(code: "customer_return_accepted", label: Language.get("Quarantine_Reason_Return_Accepted", alter: "قبول مرتجع العميل كصالح")),
                ReasonEntry(code: "quarantine_cleared", label: Language.get("Quarantine_Reason_Cleared", alter: "رفع الحجر المؤقت"))
            ]
        case .confirmDamaged:
            return [
                ReasonEntry(code: "handling_damage", label: Language.get("Damage_Reason_Handling", alter: "تلف أثناء المناولة")),
                ReasonEntry(code: "packaging_damage", label: Language.get("Damage_Reason_Packaging", alter: "تلف الغلاف الخارجي")),
                ReasonEntry(code: "manufacturing_defect", label: Language.get("Damage_Reason_Manufacturing", alter: "عيب مصنعي")),
                ReasonEntry(code: "water_damage", label: Language.get("Damage_Reason_Water", alter: "تلف سوائل/رطوبة")),
                ReasonEntry(code: "transit_damage", label: Language.get("Damage_Reason_Transit", alter: "تلف أثناء الشحن"))
            ]
        case .confirmExpired:
            return [
                ReasonEntry(code: "shelf_life_expired", label: Language.get("Expiry_Reason_Shelf_Life", alter: "انتهاء فترة الصلاحية")),
                ReasonEntry(code: "damaged_seal_expired", label: Language.get("Expiry_Reason_Seal_Broken", alter: "تلف الختم المانع للتلوث")),
                ReasonEntry(code: "recalled_batch", label: Language.get("Expiry_Reason_Recalled", alter: "تشغيلة مستدعاة"))
            ]
        case .sendToQuarantine:
            return [
                ReasonEntry(code: "inspection_required", label: Language.get("Quarantine_Reason_Inspection", alter: "طلب معاينة وفحص مخبري")),
                ReasonEntry(code: "packaging_suspect", label: Language.get("Quarantine_Reason_PackagingSuspect", alter: "اشتباه تلف الغلاف الخارجي")),
                ReasonEntry(code: "customer_return_inspection", label: Language.get("Quarantine_Reason_ReturnInspect", alter: "معاينة مرتجع عميل")),
                ReasonEntry(code: "supplier_recall", label: Language.get("Quarantine_Reason_Recall", alter: "استدعاء بضاعة للمراجعة"))
            ]
        case .returnToSupplier:
            return [
                ReasonEntry(code: "damaged_goods", label: Language.get("RTV_Reason_Damaged", alter: "بضاعة معيبة من المصدر")),
                ReasonEntry(code: "recall", label: Language.get("RTV_Reason_Recall", alter: "استدعاء رسمي من المورد")),
                ReasonEntry(code: "expired_goods", label: Language.get("RTV_Reason_Expired", alter: "منتهية الصلاحية من المورد")),
                ReasonEntry(code: "wrong_shipment", label: Language.get("RTV_Reason_Wrong", alter: "شحنة واردة بالخطأ"))
            ]
        case .physicalWriteOff:
            return [
                ReasonEntry(code: "destroyed_damaged", label: Language.get("WriteOff_Reason_Damaged", alter: "إتلاف بضاعة تالفة")),
                ReasonEntry(code: "destroyed_expired", label: Language.get("WriteOff_Reason_Expired", alter: "إتلاف منتهي الصلاحية")),
                ReasonEntry(code: "total_loss", label: Language.get("WriteOff_Reason_Loss", alter: "فقد كلي غير قابل للإصلاح")),
                ReasonEntry(code: "unrecoverable", label: Language.get("WriteOff_Reason_Unrecoverable", alter: "تعذر المعالجة"))
            ]
        }
    }
}

// MARK: - iPhone Mobile Tactile Deck

private struct iPhoneInspectionDeckView: View {
    let item: PetAccessory
    let branchRecord: PPBranchInventory?
    let availableQty: Int
    let quarantineQty: Int
    let damagedQty: Int
    let expiredQty: Int
    let supplierReturnQty: Int
    let onHandQty: Int

    @Binding var sourceBucket: String
    @Binding var quantity: Int
    let sourceAvailableCount: Int
    let sourceBucketTitle: String
    let sourceBucketColor: Color

    @Binding var selectedActionType: QuarantineStudioSheet.ActionType
    @Binding var selectedReasonCode: String
    @Binding var notes: String

    let applicableActions: [QuarantineStudioSheet.ActionType]
    let applicableReasons: [QuarantineStudioSheet.ReasonEntry]
    let pendingDispositions: [[String: Any]]
    @Binding var selectedDispositionId: String?

    let totalFinancialValue: Double
    let canReleaseQuarantine: Bool
    let isSubmitDisabled: Bool
    let isSubmitting: Bool
    let errorMessage: String?

    let onDismissError: () -> Void
    let onOpenKeypad: () -> Void
    let onSubmit: () -> Void
    let onSourceChanged: () -> Void

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: AdminSpacing.md) {
                // 1. Cinematic Product Dossier Hero Card
                InspectionProductHeroCard(item: item, onHandQty: onHandQty)

                // 2. Kinetic Routing Pipeline Banner
                KineticPipelineRouteBanner(
                    sourceTitle: sourceBucketTitle,
                    sourceColor: sourceBucketColor,
                    targetTitle: selectedActionType.title,
                    targetColor: selectedActionType.accentColor,
                    quantity: quantity,
                    financialValue: totalFinancialValue,
                    isWriteOff: selectedActionType.isWriteOff
                )

                // 3. Multi-Bucket Allocation Strip
                BucketAllocationBarometer(
                    available: availableQty,
                    quarantine: quarantineQty,
                    damaged: damagedQty,
                    expired: expiredQty,
                    supplierReturn: supplierReturnQty,
                    selectedBucket: $sourceBucket,
                    onBucketSelected: {
                        quantity = min(max(1, quantity), max(1, sourceAvailableCount))
                        onSourceChanged()
                    }
                )

                // 4. Tactile Ergonomic Quantity Station
                TactileQuantityControlStation(
                    quantity: $quantity,
                    maxQuantity: sourceAvailableCount,
                    unitPrice: item.finalPrice.doubleValue,
                    onOpenKeypad: onOpenKeypad
                )

                // 5. Categorized Action Matrix
                VStack(alignment: .leading, spacing: AdminSpacing.xs) {
                    Text(Language.get("Quarantine_Choose_Disposition", alter: "قرار الفحص والتوجيه الإداري"))
                        .font(AdminType.captionBold)
                        .foregroundColor(AdminSurface.secondaryText)

                    VStack(spacing: 8) {
                        ForEach(applicableActions) { action in
                            InspectionActionCard(
                                action: action,
                                isSelected: selectedActionType == action,
                                canRelease: canReleaseQuarantine,
                                onSelect: {
                                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                    selectedActionType = action
                                    onSourceChanged()
                                }
                            )
                        }
                    }
                }

                // 6. Contextual Reason Chips
                VStack(alignment: .leading, spacing: AdminSpacing.xs) {
                    Text(Language.get("Reason", alter: "سبب التصرف المعياري"))
                        .font(AdminType.captionBold)
                        .foregroundColor(AdminSurface.secondaryText)

                    ReasonChipFlowLayout(
                        reasons: applicableReasons,
                        selectedCode: $selectedReasonCode,
                        accentColor: selectedActionType.accentColor
                    )
                }

                // 7. Linked Customer Dispositions (if POS return attached)
                if !pendingDispositions.isEmpty {
                    LinkedDispositionsDrawer(
                        dispositions: pendingDispositions,
                        selectedId: $selectedDispositionId,
                        onSelectQty: { qty in
                            quantity = min(qty, sourceAvailableCount)
                        }
                    )
                }

                // 8. Audit Notes Editor with Quick Tags
                InspectionNotesStudioCard(
                    notes: $notes,
                    onAppendTag: { tag in
                        if notes.isEmpty {
                            notes = tag
                        } else {
                            notes += " • " + tag
                        }
                    }
                )

                // 9. Error Banner if present
                if let errorMessage = errorMessage {
                    AdminErrorBanner(message: errorMessage) {
                        onDismissError()
                    }
                }

                // Bottom spacer for floating dock
                Spacer().frame(height: 90)
            }
            .padding(.horizontal, AdminSpacing.screenMargin)
            .padding(.top, AdminSpacing.sm)
        }
        .clipped()
        .safeAreaInset(edge: .bottom) {
            // Floating Command Dock
            FloatingExecutionCommandDock(
                actionType: selectedActionType,
                quantity: quantity,
                totalValue: totalFinancialValue,
                isDisabled: isSubmitDisabled,
                isSubmitting: isSubmitting,
                onSubmit: onSubmit
            )
        }
    }
}

// MARK: - iPad Dual-Pane Command Cockpit

private struct iPadInspectionCockpitView: View {
    let item: PetAccessory
    let branchRecord: PPBranchInventory?
    let availableQty: Int
    let quarantineQty: Int
    let damagedQty: Int
    let expiredQty: Int
    let supplierReturnQty: Int
    let onHandQty: Int

    @Binding var sourceBucket: String
    @Binding var quantity: Int
    let sourceAvailableCount: Int
    let sourceBucketTitle: String
    let sourceBucketColor: Color

    @Binding var selectedActionType: QuarantineStudioSheet.ActionType
    @Binding var selectedReasonCode: String
    @Binding var notes: String

    let applicableActions: [QuarantineStudioSheet.ActionType]
    let applicableReasons: [QuarantineStudioSheet.ReasonEntry]
    let pendingDispositions: [[String: Any]]
    @Binding var selectedDispositionId: String?

    let totalFinancialValue: Double
    let canReleaseQuarantine: Bool
    let isSubmitDisabled: Bool
    let isSubmitting: Bool
    let errorMessage: String?

    let onDismissError: () -> Void
    let onOpenKeypad: () -> Void
    let onSubmit: () -> Void
    let onSourceChanged: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            // Leading Master Pane: Inspection Telemetry & Allocation Radar (380pt)
            VStack(spacing: AdminSpacing.md) {
                ScrollView(showsIndicators: false) {
                    VStack(spacing: AdminSpacing.md) {
                        // High-Def Product Hero
                        InspectionProductHeroCard(item: item, onHandQty: onHandQty, isWidescreen: true)

                        // 5-Bucket Radial Allocation Radar
                        RadialBucketAllocationDial(
                            available: availableQty,
                            quarantine: quarantineQty,
                            damaged: damagedQty,
                            expired: expiredQty,
                            supplierReturn: supplierReturnQty,
                            onHand: onHandQty
                        )

                        // Financial Valuation & Economic Impact HUD
                        FinancialImpactExecutiveHUD(
                            unitPrice: item.finalPrice.doubleValue,
                            quantity: quantity,
                            totalValue: totalFinancialValue,
                            actionType: selectedActionType
                        )

                        // Linked Claims Drawer
                        if !pendingDispositions.isEmpty {
                            LinkedDispositionsDrawer(
                                dispositions: pendingDispositions,
                                selectedId: $selectedDispositionId,
                                onSelectQty: { qty in
                                    quantity = min(qty, sourceAvailableCount)
                                }
                            )
                        }
                    }
                    .padding(AdminSpacing.lg)
                }
                .clipped()
            }
            .frame(width: 380)
            .background(AdminSurface.surface)
            .overlay(
                Rectangle()
                    .fill(AdminSurface.hairline)
                    .frame(width: 1),
                alignment: .trailing
            )

            // Trailing Detail Pane: Kinetic Pipeline & Disposition Routing Deck
            VStack(spacing: 0) {
                ScrollView(showsIndicators: false) {
                    VStack(spacing: AdminSpacing.lg) {
                        // Error Banner
                        if let errorMessage = errorMessage {
                            AdminErrorBanner(message: errorMessage) {
                                onDismissError()
                            }
                        }

                        // Kinetic Flow Router Canvas
                        KineticPipelineRouteBanner(
                            sourceTitle: sourceBucketTitle,
                            sourceColor: sourceBucketColor,
                            targetTitle: selectedActionType.title,
                            targetColor: selectedActionType.accentColor,
                            quantity: quantity,
                            financialValue: totalFinancialValue,
                            isWriteOff: selectedActionType.isWriteOff
                        )

                        // Interactive Bucket Selector with capacity meters
                        BucketAllocationBarometer(
                            available: availableQty,
                            quarantine: quarantineQty,
                            damaged: damagedQty,
                            expired: expiredQty,
                            supplierReturn: supplierReturnQty,
                            selectedBucket: $sourceBucket,
                            onBucketSelected: {
                                quantity = min(max(1, quantity), max(1, sourceAvailableCount))
                                onSourceChanged()
                            }
                        )

                        // Tactile Quantity Station with Quick Multipliers
                        TactileQuantityControlStation(
                            quantity: $quantity,
                            maxQuantity: sourceAvailableCount,
                            unitPrice: item.finalPrice.doubleValue,
                            onOpenKeypad: onOpenKeypad
                        )

                        // 2-Column Action Grid
                        VStack(alignment: .leading, spacing: AdminSpacing.sm) {
                            Text(Language.get("Quarantine_Choose_Disposition", alter: "قرار الفحص والتوجيه الإداري"))
                                .font(AdminType.calloutBold)
                                .foregroundColor(AdminSurface.primaryText)

                            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                                ForEach(applicableActions) { action in
                                    InspectionActionCard(
                                        action: action,
                                        isSelected: selectedActionType == action,
                                        canRelease: canReleaseQuarantine,
                                        onSelect: {
                                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                            selectedActionType = action
                                            onSourceChanged()
                                        }
                                    )
                                }
                            }
                        }

                        // Contextual Reason Cloud
                        VStack(alignment: .leading, spacing: AdminSpacing.xs) {
                            Text(Language.get("Reason", alter: "سبب التصرف المعياري"))
                                .font(AdminType.captionBold)
                                .foregroundColor(AdminSurface.secondaryText)

                            ReasonChipFlowLayout(
                                reasons: applicableReasons,
                                selectedCode: $selectedReasonCode,
                                accentColor: selectedActionType.accentColor
                            )
                        }

                        // Notes Editor Studio
                        InspectionNotesStudioCard(
                            notes: $notes,
                            onAppendTag: { tag in
                                if notes.isEmpty {
                                    notes = tag
                                } else {
                                    notes += " • " + tag
                                }
                            }
                        )
                    }
                    .padding(AdminSpacing.xl)
                }
                .clipped()

                // Sticky Bottom Execution Dock
                VStack(spacing: 0) {
                    Divider().background(AdminSurface.hairline)

                    HStack(spacing: AdminSpacing.lg) {
                        VStack(alignment: .leading, spacing: 3) {
                            HStack(spacing: 6) {
                                Circle().fill(selectedActionType.accentColor).frame(width: 8, height: 8)
                                Text(verbatim: "\(selectedActionType.title) (\(quantity))".normalizedEnglishDigits)
                                    .font(AdminType.headlineBold)
                                    .foregroundColor(AdminSurface.primaryText)
                            }
                            Text(verbatim: String(format: "%.2f QAR", totalFinancialValue).normalizedEnglishDigits)
                                .font(AdminType.captionBold)
                                .foregroundColor(selectedActionType.accentColor)
                        }

                        Spacer()

                        Button(action: onSubmit) {
                            HStack(spacing: 8) {
                                if isSubmitting {
                                    ProgressView().tint(.white)
                                } else {
                                    Image(systemName: selectedActionType.iconName)
                                        .font(.system(size: 16, weight: .bold))
                                    Text(selectedActionType.isWriteOff ? Language.get("Quarantine_Execute_Writeoff", alter: "اعتماد الشطب النهائي") : Language.get("Quarantine_Execute_Action", alter: "اعتماد وتنفيذ التوجيه"))
                                        .font(AdminType.calloutBold)
                                }
                            }
                            .padding(.horizontal, 28)
                            .padding(.vertical, 14)
                            .background(isSubmitDisabled ? AdminSurface.control : selectedActionType.accentColor, in: RoundedRectangle(cornerRadius: AdminRadius.card))
                            .foregroundColor(isSubmitDisabled ? AdminSurface.secondaryText : .white)
                        }
                        .disabled(isSubmitDisabled)
                    }
                    .padding(.horizontal, AdminSpacing.xl)
                    .padding(.vertical, AdminSpacing.md)
                    .background(AdminSurface.surface)
                }
            }
        }
    }
}

// MARK: - Subcomponents: Product Hero Card

private struct InspectionProductHeroCard: View {
    let item: PetAccessory
    let onHandQty: Int
    var isWidescreen: Bool = false

    var body: some View {
        HStack(spacing: AdminSpacing.md) {
            ZStack {
                RoundedRectangle(cornerRadius: AdminRadius.card)
                    .fill(AdminSurface.control)
                    .frame(width: isWidescreen ? 76 : 64, height: isWidescreen ? 76 : 64)

                if let first = item.imageURLsArray.first, !first.isEmpty, let url = URL(string: first) {
                    AsyncImage(url: url) { img in
                        img.resizable().aspectRatio(contentMode: .fill)
                    } placeholder: {
                        Image(systemName: "cube.box.fill")
                            .foregroundColor(AdminSurface.secondaryText)
                    }
                    .frame(width: isWidescreen ? 76 : 64, height: isWidescreen ? 76 : 64)
                    .clipShape(RoundedRectangle(cornerRadius: AdminRadius.card))
                } else {
                    Image(systemName: "cube.box.fill")
                        .font(.system(size: isWidescreen ? 30 : 24))
                        .foregroundColor(AdminSurface.secondaryText)
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(item.name)
                    .font(AdminType.calloutBold)
                    .foregroundColor(AdminSurface.primaryText)
                    .lineLimit(2)

                HStack(spacing: 8) {
                    if let sku = item.sku, !sku.isEmpty {
                        Text(verbatim: "SKU: \(sku)".normalizedEnglishDigits)
                            .font(AdminType.caption2Bold)
                            .foregroundColor(AdminSurface.secondaryText)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: 4))
                    }

                    Text(verbatim: String(format: "%.2f QAR", item.finalPrice.doubleValue).normalizedEnglishDigits)
                        .font(AdminType.captionBold)
                        .foregroundColor(AdminSurface.primary)
                }

                HStack(spacing: 8) {
                    if let branchName = BranchContextStore.shared.activeBranch?.localizedName(), !branchName.isEmpty {
                        HStack(spacing: 3) {
                            Image(systemName: "mappin.and.ellipse")
                                .font(.system(size: 9))
                            Text(branchName)
                                .font(AdminType.caption2)
                        }
                        .foregroundColor(AdminSurface.secondaryText.opacity(0.85))
                    }

                    Spacer()

                    Text(verbatim: "\(Language.get("Inventory_On_Hand", alter: "العهدة")): \(onHandQty)".normalizedEnglishDigits)
                        .font(AdminType.caption2Bold)
                        .foregroundColor(AdminSurface.primaryText)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(AdminSurface.control, in: Capsule())
                }
            }
        }
        .padding(AdminSpacing.md)
        .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: AdminRadius.card))
        .overlay(RoundedRectangle(cornerRadius: AdminRadius.card).stroke(AdminSurface.hairline))
    }
}

// MARK: - Subcomponents: Kinetic Pipeline Route Banner

private struct KineticPipelineRouteBanner: View {
    let sourceTitle: String
    let sourceColor: Color
    let targetTitle: String
    let targetColor: Color
    let quantity: Int
    let financialValue: Double
    let isWriteOff: Bool

    var body: some View {
        HStack(spacing: 12) {
            // Source Node
            HStack(spacing: 6) {
                Circle().fill(sourceColor).frame(width: 8, height: 8)
                Text(sourceTitle)
                    .font(AdminType.captionBold)
                    .foregroundColor(AdminSurface.primaryText)
                    .lineLimit(1)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(sourceColor.opacity(0.12), in: Capsule())

            // Vector Connector
            VStack(spacing: 2) {
                HStack(spacing: 3) {
                    Rectangle().fill(AdminSurface.hairline).frame(height: 1.5)
                    Image(systemName: "arrow.left")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(targetColor)
                    Rectangle().fill(AdminSurface.hairline).frame(height: 1.5)
                }

                Text(verbatim: "\(quantity) \(Language.get("Units", alter: "قطع"))".normalizedEnglishDigits)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(AdminSurface.secondaryText)
            }
            .frame(maxWidth: .infinity)

            // Target Node
            HStack(spacing: 6) {
                Circle().fill(targetColor).frame(width: 8, height: 8)
                Text(targetTitle)
                    .font(AdminType.captionBold)
                    .foregroundColor(AdminSurface.primaryText)
                    .lineLimit(1)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(targetColor.opacity(0.12), in: Capsule())
        }
        .padding(AdminSpacing.md)
        .background(
            RoundedRectangle(cornerRadius: AdminRadius.card)
                .fill(targetColor.opacity(0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: AdminRadius.card)
                .stroke(targetColor.opacity(0.2), lineWidth: 1)
        )
    }
}

// MARK: - Subcomponents: 5-Bucket Allocation Barometer

private struct BucketAllocationBarometer: View {
    let available: Int
    let quarantine: Int
    let damaged: Int
    let expired: Int
    let supplierReturn: Int
    @Binding var selectedBucket: String
    let onBucketSelected: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: AdminSpacing.xs) {
            Text(Language.get("Quarantine_Source_Bucket", alter: "وعاء المصدر (المخزون المراد فحصه)"))
                .font(AdminType.captionBold)
                .foregroundColor(AdminSurface.secondaryText)

            HStack(spacing: 6) {
                bucketChip(key: "quarantine", label: Language.get("Inventory_Quarantine", alter: "حجر الفحص"), count: quarantine, color: .violet, icon: "shield.lefthalf.filled")
                bucketChip(key: "damaged", label: Language.get("Inventory_Damaged", alter: "التوالف"), count: damaged, color: .amber, icon: "exclamationmark.triangle.fill")
                bucketChip(key: "expired", label: Language.get("Inventory_Expired", alter: "المنتهي"), count: expired, color: .crimson, icon: "clock.badge.xmark.fill")
                bucketChip(key: "supplierReturn", label: Language.get("Inventory_Supplier_Return", alter: "مرتجع مورد"), count: supplierReturn, color: .sapphire, icon: "arrow.uturn.backward.circle.fill")
                bucketChip(key: "available", label: Language.get("Inventory_Available", alter: "متوفر"), count: available, color: .emerald, icon: "checkmark.circle.fill")
            }
        }
    }

    private func bucketChip(key: String, label: String, count: Int, color: Color, icon: String) -> some View {
        let isSelected = selectedBucket == key
        let isEmpty = count <= 0

        return Button {
            guard count > 0 else {
                UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
                return
            }
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            selectedBucket = key
            onBucketSelected()
        } label: {
            VStack(spacing: 4) {
                HStack(spacing: 3) {
                    Image(systemName: icon)
                        .font(.system(size: 10))
                        .foregroundColor(isEmpty ? AdminSurface.secondaryText.opacity(0.4) : color)
                    Text(verbatim: "\(count)".normalizedEnglishDigits)
                        .font(AdminType.captionBold)
                        .foregroundColor(isEmpty ? AdminSurface.secondaryText.opacity(0.6) : AdminSurface.primaryText)
                }

                Text(label)
                    .font(.system(size: 9, weight: isSelected ? .bold : .medium))
                    .foregroundColor(isSelected ? color : AdminSurface.secondaryText)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(isSelected ? color.opacity(0.16) : AdminSurface.surface, in: RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(isSelected ? color : AdminSurface.hairline, lineWidth: isSelected ? 1.5 : 1)
            )
            .opacity(isEmpty && !isSelected ? 0.45 : 1.0)
        }
        .disabled(isEmpty)
        .buttonStyle(.plain)
    }
}

// MARK: - Subcomponents: Tactile Quantity Control Station

private struct TactileQuantityControlStation: View {
    @Binding var quantity: Int
    let maxQuantity: Int
    let unitPrice: Double
    let onOpenKeypad: () -> Void

    var body: some View {
        VStack(spacing: AdminSpacing.sm) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(Language.get("Quantity", alter: "الكمية الموجهة للفحص"))
                        .font(AdminType.calloutBold)
                        .foregroundColor(AdminSurface.primaryText)

                    Text(verbatim: "\(Language.get("Quarantine_Available_In_Bucket", alter: "المتوفر في الوعاء")): \(maxQuantity)".normalizedEnglishDigits)
                        .font(AdminType.caption2)
                        .foregroundColor(maxQuantity > 0 ? AdminSurface.secondaryText : .red)
                }

                Spacer()

                // Tap Count Bubble for Precision Keypad Modal
                Button(action: onOpenKeypad) {
                    HStack(spacing: 4) {
                        Image(systemName: "keyboard")
                            .font(.system(size: 11))
                        Text(verbatim: "\(quantity)".normalizedEnglishDigits)
                            .font(.system(size: 22, weight: .bold, design: .rounded))
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
                    .background(AdminSurface.control, in: Capsule())
                    .foregroundColor(AdminSurface.primaryText)
                    .overlay(Capsule().stroke(AdminSurface.primary.opacity(0.3), lineWidth: 1))
                }
            }

            // Tactile Stepper & Quick Presets
            HStack(spacing: 10) {
                // Minus Stepper
                Button {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    if quantity > 1 { quantity -= 1 }
                } label: {
                    Image(systemName: "minus")
                        .font(.system(size: 16, weight: .bold))
                        .frame(width: 44, height: 40)
                        .background(quantity > 1 ? AdminSurface.control : AdminSurface.control.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
                        .foregroundColor(quantity > 1 ? AdminSurface.primaryText : AdminSurface.secondaryText)
                }
                .disabled(quantity <= 1)

                // Plus Stepper
                Button {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    if quantity < maxQuantity { quantity += 1 }
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 16, weight: .bold))
                        .frame(width: 44, height: 40)
                        .background(quantity < maxQuantity ? AdminSurface.control : AdminSurface.control.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
                        .foregroundColor(quantity < maxQuantity ? AdminSurface.primaryText : AdminSurface.secondaryText)
                }
                .disabled(quantity >= maxQuantity)

                Spacer()

                // Quick Presets (+5, +10, All)
                ForEach([5, 10], id: \.self) { delta in
                    Button {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        quantity = min(maxQuantity, quantity + delta)
                    } label: {
                        Text(verbatim: "+\(delta)".normalizedEnglishDigits)
                            .font(AdminType.captionBold)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 8)
                            .background(AdminSurface.control, in: Capsule())
                            .foregroundColor(AdminSurface.primaryText)
                    }
                    .disabled(quantity >= maxQuantity)
                }

                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    quantity = max(1, maxQuantity)
                } label: {
                    Text(Language.get("All", alter: "الكل"))
                        .font(AdminType.captionBold)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(AdminSurface.primary.opacity(0.12), in: Capsule())
                        .foregroundColor(AdminSurface.primary)
                }
                .disabled(maxQuantity <= 0)
            }
        }
        .padding(AdminSpacing.md)
        .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: AdminRadius.card))
        .overlay(RoundedRectangle(cornerRadius: AdminRadius.card).stroke(AdminSurface.hairline))
    }
}

// MARK: - Subcomponents: Inspection Action Card

private struct InspectionActionCard: View {
    let action: QuarantineStudioSheet.ActionType
    let isSelected: Bool
    let canRelease: Bool
    let onSelect: () -> Void

    private var isBlocked: Bool {
        action == .releaseToStock && !canRelease
    }

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: AdminSpacing.md) {
                Image(systemName: action.iconName)
                    .font(.system(size: 20))
                    .foregroundColor(action.accentColor)
                    .frame(width: 38, height: 38)
                    .background(action.accentColor.opacity(0.14), in: RoundedRectangle(cornerRadius: 10))

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(action.title)
                            .font(AdminType.calloutBold)
                            .foregroundColor(AdminSurface.primaryText)

                        if isBlocked {
                            HStack(spacing: 3) {
                                Image(systemName: "lock.fill")
                                    .font(.system(size: 8))
                                Text(Language.get("Quarantine_Perm_Locked", alter: "صلاحية مقيدة"))
                                    .font(.system(size: 9, weight: .bold))
                            }
                            .foregroundColor(.amber)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.amber.opacity(0.12), in: Capsule())
                        }
                    }

                    Text(action.subtitle)
                        .font(AdminType.caption2)
                        .foregroundColor(AdminSurface.secondaryText)
                        .lineLimit(2)
                }

                Spacer()

                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 20))
                    .foregroundColor(isSelected ? action.accentColor : AdminSurface.control)
            }
            .padding(AdminSpacing.md)
            .background(isSelected ? action.accentColor.opacity(0.06) : AdminSurface.surface, in: RoundedRectangle(cornerRadius: AdminRadius.card))
            .overlay(
                RoundedRectangle(cornerRadius: AdminRadius.card)
                    .stroke(isSelected ? action.accentColor : AdminSurface.hairline, lineWidth: isSelected ? 1.5 : 1)
            )
            .opacity(isBlocked ? 0.6 : 1.0)
        }
        .buttonStyle(.plain)
        .disabled(isBlocked)
    }
}

// MARK: - Subcomponents: Reason Chips

private struct ReasonChipFlowLayout: View {
    let reasons: [QuarantineStudioSheet.ReasonEntry]
    @Binding var selectedCode: String
    let accentColor: Color

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(reasons) { entry in
                    let isSelected = selectedCode == entry.code
                    Button {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        selectedCode = entry.code
                    } label: {
                        Text(entry.label)
                            .font(AdminType.captionBold)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(isSelected ? accentColor : AdminSurface.surface, in: Capsule())
                            .foregroundColor(isSelected ? .white : AdminSurface.secondaryText)
                            .overlay(Capsule().stroke(isSelected ? accentColor : AdminSurface.hairline))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 2)
            .padding(.vertical, 4)
        }
    }
}

// MARK: - Subcomponents: Linked Dispositions Drawer

private struct LinkedDispositionsDrawer: View {
    let dispositions: [[String: Any]]
    @Binding var selectedId: String?
    let onSelectQty: (Int) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: AdminSpacing.xs) {
            Text(Language.get("Quarantine_Linked_POS_Returns", alter: "مرتجعات عملاء بانتظار الفحص"))
                .font(AdminType.captionBold)
                .foregroundColor(AdminSurface.secondaryText)

            VStack(spacing: 6) {
                ForEach(dispositions.indices, id: \.self) { index in
                    let disp = dispositions[index]
                    let dispId = (disp["dispositionId"] as? String) ?? ""
                    let isSelected = selectedId == dispId
                    let dispQty = (disp["quantity"] as? Int) ?? 1
                    let txId = (disp["sourceTransactionId"] as? String) ?? ""

                    Button {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        if isSelected {
                            selectedId = nil
                        } else {
                            selectedId = dispId
                            onSelectQty(dispQty)
                        }
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                HStack(spacing: 4) {
                                    Text(verbatim: "\(Language.get("Quarantine_Return_Doc", alter: "طلب مرتجع")): \(dispId)".normalizedEnglishDigits)
                                        .font(AdminType.captionBold)
                                        .foregroundColor(AdminSurface.primaryText)
                                        .lineLimit(1)

                                    Text(verbatim: "\(dispQty) \(Language.get("Units", alter: "قطع"))".normalizedEnglishDigits)
                                        .font(AdminType.caption2Bold)
                                        .foregroundColor(.violet)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(Color.violet.opacity(0.12), in: Capsule())
                                }

                                if !txId.isEmpty {
                                    Text(verbatim: "\(Language.get("Transaction", alter: "رقم الفاتورة")): \(txId)".normalizedEnglishDigits)
                                        .font(.system(size: 10))
                                        .foregroundColor(AdminSurface.secondaryText)
                                }
                            }

                            Spacer()

                            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                                .foregroundColor(isSelected ? AdminSurface.primary : AdminSurface.control)
                        }
                        .padding(AdminSpacing.sm)
                        .background(isSelected ? AdminSurface.primary.opacity(0.08) : AdminSurface.surface, in: RoundedRectangle(cornerRadius: AdminRadius.medium))
                        .overlay(RoundedRectangle(cornerRadius: AdminRadius.medium).stroke(isSelected ? AdminSurface.primary : AdminSurface.hairline))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

// MARK: - Subcomponents: Inspection Notes Studio Card

private struct InspectionNotesStudioCard: View {
    @Binding var notes: String
    let onAppendTag: (String) -> Void

    private let quickTags = [
        "فحص ظاهري سليم",
        "تلف تغليف كرتوني",
        "كسر أثناء الشحن",
        "انتهاء صلاحية المورد"
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: AdminSpacing.xs) {
            Text(Language.get("Notes", alter: "تقرير وملاحظات الفحص"))
                .font(AdminType.captionBold)
                .foregroundColor(AdminSurface.secondaryText)

            TextField(
                Language.get("Quarantine_Notes_Placeholder", alter: "اكتب تقرير الفحص المخبري أو حالة البضاعة..."),
                text: $notes
            )
            .font(AdminType.body)
            .padding(AdminSpacing.md)
            .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: AdminRadius.card))
            .overlay(RoundedRectangle(cornerRadius: AdminRadius.card).stroke(AdminSurface.hairline))

            // Quick Tag Chips
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(quickTags, id: \.self) { tag in
                        Button {
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            onAppendTag(tag)
                        } label: {
                            Text(verbatim: "+ \(tag)")
                                .font(AdminType.caption2)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(AdminSurface.control, in: Capsule())
                                .foregroundColor(AdminSurface.secondaryText)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 2)
            }
        }
    }
}

// MARK: - Subcomponents: Floating Execution Command Dock (iPhone)

private struct FloatingExecutionCommandDock: View {
    let actionType: QuarantineStudioSheet.ActionType
    let quantity: Int
    let totalValue: Double
    let isDisabled: Bool
    let isSubmitting: Bool
    let onSubmit: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: AdminSpacing.md) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 4) {
                        Circle().fill(actionType.accentColor).frame(width: 8, height: 8)
                        Text(verbatim: "\(actionType.title)".normalizedEnglishDigits)
                            .font(AdminType.captionBold)
                            .foregroundColor(AdminSurface.primaryText)
                            .lineLimit(1)
                    }
                    Text(verbatim: String(format: "%.2f QAR", totalValue).normalizedEnglishDigits)
                        .font(AdminType.headlineBold)
                        .foregroundColor(actionType.accentColor)
                }

                Spacer()

                Button(action: onSubmit) {
                    HStack(spacing: 8) {
                        if isSubmitting {
                            ProgressView().tint(.white)
                        } else {
                            Image(systemName: actionType.iconName)
                                .font(.system(size: 15, weight: .bold))
                            Text(actionType.isWriteOff ? Language.get("Quarantine_Execute_Writeoff", alter: "شطب نهائي") : Language.get("Confirm", alter: "تأكيد التنفيذ"))
                                .font(AdminType.calloutBold)
                        }
                    }
                    .padding(.horizontal, 22)
                    .padding(.vertical, 12)
                    .background(isDisabled ? AdminSurface.control : actionType.accentColor, in: RoundedRectangle(cornerRadius: AdminRadius.card))
                    .foregroundColor(isDisabled ? AdminSurface.secondaryText : .white)
                }
                .disabled(isDisabled)
            }
            .padding(.horizontal, AdminSpacing.md)
            .padding(.vertical, AdminSpacing.sm)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18))
            .overlay(RoundedRectangle(cornerRadius: 18).stroke(AdminSurface.hairline))
            .shadow(color: Color.black.opacity(0.08), radius: 10, y: 4)
            .padding(.horizontal, AdminSpacing.screenMargin)
            .padding(.bottom, AdminSpacing.xs)
        }
    }
}

// MARK: - Subcomponents: Radial Allocation Dial (iPad)

private struct RadialBucketAllocationDial: View {
    let available: Int
    let quarantine: Int
    let damaged: Int
    let expired: Int
    let supplierReturn: Int
    let onHand: Int

    var body: some View {
        VStack(spacing: AdminSpacing.md) {
            Text(Language.get("Quarantine_Allocation_Radar", alter: "رادار توزيع المخزون"))
                .font(AdminType.calloutBold)
                .foregroundColor(AdminSurface.primaryText)

            ZStack {
                // Background Track
                Circle()
                    .stroke(AdminSurface.control, lineWidth: 16)
                    .frame(width: 140, height: 140)

                // Segment indicators (Approximation of proportional rings)
                Circle()
                    .trim(from: 0.0, to: max(0.01, min(1.0, onHand > 0 ? Double(available) / Double(onHand) : 0)))
                    .stroke(Color.emerald, style: StrokeStyle(lineWidth: 16, lineCap: .round))
                    .frame(width: 140, height: 140)
                    .rotationEffect(.degrees(-90))

                VStack(spacing: 2) {
                    Text(verbatim: "\(onHand)".normalizedEnglishDigits)
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .foregroundColor(AdminSurface.primaryText)
                    Text(Language.get("Inventory_On_Hand", alter: "العهدة الفعلية"))
                        .font(AdminType.caption2)
                        .foregroundColor(AdminSurface.secondaryText)
                }
            }
            .frame(height: 150)

            // Legend Grid
            HStack(spacing: 12) {
                legendPill(title: Language.get("Inventory_Available", alter: "متوفر"), count: available, color: .emerald)
                legendPill(title: Language.get("Inventory_Quarantine", alter: "حجر"), count: quarantine, color: .violet)
                legendPill(title: Language.get("Inventory_Damaged", alter: "تالف"), count: damaged, color: .amber)
                legendPill(title: Language.get("Inventory_Expired", alter: "منتهي"), count: expired, color: .crimson)
            }
        }
        .padding(AdminSpacing.md)
        .background(AdminSurface.control.opacity(0.35), in: RoundedRectangle(cornerRadius: AdminRadius.card))
        .overlay(RoundedRectangle(cornerRadius: AdminRadius.card).stroke(AdminSurface.hairline))
    }

    private func legendPill(title: String, count: Int, color: Color) -> some View {
        VStack(spacing: 2) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text(verbatim: "\(count)".normalizedEnglishDigits)
                .font(AdminType.captionBold)
                .foregroundColor(AdminSurface.primaryText)
            Text(title)
                .font(.system(size: 8))
                .foregroundColor(AdminSurface.secondaryText)
        }
    }
}

// MARK: - Subcomponents: Financial Impact Executive HUD (iPad)

private struct FinancialImpactExecutiveHUD: View {
    let unitPrice: Double
    let quantity: Int
    let totalValue: Double
    let actionType: QuarantineStudioSheet.ActionType

    var body: some View {
        VStack(alignment: .leading, spacing: AdminSpacing.sm) {
            Text(Language.get("Quarantine_Financial_Impact", alter: "التقييم المالي والأثر التشغيلي"))
                .font(AdminType.captionBold)
                .foregroundColor(AdminSurface.secondaryText)

            VStack(spacing: 8) {
                HStack {
                    Text(Language.get("Quarantine_Unit_Price", alter: "سعر بيع الوحدة"))
                        .font(AdminType.caption)
                        .foregroundColor(AdminSurface.secondaryText)
                    Spacer()
                    Text(verbatim: String(format: "%.2f QAR", unitPrice).normalizedEnglishDigits)
                        .font(AdminType.captionBold)
                        .foregroundColor(AdminSurface.primaryText)
                }

                Divider().background(AdminSurface.hairline)

                HStack {
                    Text(Language.get("Quarantine_Total_Value", alter: "القيمة الإجمالية المعالجة"))
                        .font(AdminType.caption)
                        .foregroundColor(AdminSurface.secondaryText)
                    Spacer()
                    Text(verbatim: String(format: "%.2f QAR", totalValue).normalizedEnglishDigits)
                        .font(AdminType.headlineBold)
                        .foregroundColor(actionType.accentColor)
                }

                HStack {
                    Text(Language.get("Quarantine_Operational_Impact", alter: "الأثر على الميزانية"))
                        .font(AdminType.caption2)
                        .foregroundColor(AdminSurface.secondaryText)
                    Spacer()
                    Text(impactDescription)
                        .font(AdminType.caption2Bold)
                        .foregroundColor(actionType.accentColor)
                }
            }
            .padding(AdminSpacing.md)
            .background(actionType.accentColor.opacity(0.06), in: RoundedRectangle(cornerRadius: AdminRadius.medium))
            .overlay(RoundedRectangle(cornerRadius: AdminRadius.medium).stroke(actionType.accentColor.opacity(0.2)))
        }
    }

    private var impactDescription: String {
        switch actionType {
        case .releaseToStock:
            return Language.get("Quarantine_Impact_Reclaimed", alter: "+ استرداد لقيمة المبيعات")
        case .confirmDamaged:
            return Language.get("Quarantine_Impact_Damaged", alter: "تجميد بانتظار المطالبة")
        case .confirmExpired:
            return Language.get("Quarantine_Impact_Expired", alter: "جاهز لقرار الشطب")
        case .returnToSupplier:
            return Language.get("Quarantine_Impact_RTV", alter: "استرداد نقدي من المورد")
        case .physicalWriteOff:
            return Language.get("Quarantine_Impact_Loss", alter: "- شطب خسارة تشغيلية")
        case .sendToQuarantine:
            return Language.get("Quarantine_Impact_Quarantined", alter: "حجز مؤقت للفحص")
        }
    }
}

// MARK: - Subcomponents: Precision Numeric Keypad Modal

private struct QuarantinePrecisionKeypadModal: View {
    let maxQuantity: Int
    let initialQuantity: Int
    let onCommit: (Int) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var inputBuffer: String = ""

    private let keypadRows: [[String]] = [
        ["1", "2", "3"],
        ["4", "5", "6"],
        ["7", "8", "9"],
        ["C", "0", "⌫"]
    ]

    var body: some View {
        VStack(spacing: AdminSpacing.md) {
            Text(Language.get("Quarantine_Enter_Exact_Qty", alter: "إدخال الكمية بدقة"))
                .font(AdminType.headlineBold)
                .foregroundColor(AdminSurface.primaryText)
                .padding(.top, AdminSpacing.md)

            // Preview Display
            HStack {
                Spacer()
                Text(verbatim: "\(displayQuantity)".normalizedEnglishDigits)
                    .font(.system(size: 40, weight: .bold, design: .rounded))
                    .foregroundColor(AdminSurface.primaryText)
                Text(Language.get("Units", alter: "قطع"))
                    .font(AdminType.calloutBold)
                    .foregroundColor(AdminSurface.secondaryText)
                Spacer()
            }
            .padding(.vertical, 8)
            .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: AdminRadius.card))

            // Quick Preset Chips
            HStack(spacing: 8) {
                presetButton(label: "+1", add: 1)
                presetButton(label: "+5", add: 5)
                presetButton(label: "+10", add: 10)
                presetButton(label: Language.get("All", alter: "الكل"), absolute: maxQuantity)
            }

            // 10-Key Grid
            VStack(spacing: 10) {
                ForEach(keypadRows, id: \.self) { row in
                    HStack(spacing: 12) {
                        ForEach(row, id: \.self) { key in
                            Button {
                                handleKey(key)
                            } label: {
                                Text(verbatim: key.normalizedEnglishDigits)
                                    .font(.system(size: 22, weight: .bold, design: .rounded))
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 52)
                                    .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: 12))
                                    .foregroundColor(key == "C" ? .red : AdminSurface.primaryText)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }

            // Commit Button
            Button {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                onCommit(displayQuantity)
                dismiss()
            } label: {
                Text(Language.get("Quarantine_Commit_Qty", alter: "تأكيد الكمية"))
                    .font(AdminType.calloutBold)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(AdminSurface.primary, in: RoundedRectangle(cornerRadius: AdminRadius.card))
                    .foregroundColor(.white)
            }
            .padding(.bottom, AdminSpacing.md)
        }
        .padding(.horizontal, AdminSpacing.lg)
        .onAppear {
            inputBuffer = "\(initialQuantity)"
        }
    }

    private var displayQuantity: Int {
        if let val = Int(inputBuffer), val > 0 {
            return min(val, maxQuantity)
        }
        return 1
    }

    private func handleKey(_ key: String) {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        switch key {
        case "C":
            inputBuffer = ""
        case "⌫":
            if !inputBuffer.isEmpty {
                inputBuffer.removeLast()
            }
        default:
            if inputBuffer.count < 5 {
                inputBuffer.append(key)
            }
        }
    }

    private func presetButton(label: String, add: Int? = nil, absolute: Int? = nil) -> some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            if let add = add {
                let current = displayQuantity
                inputBuffer = "\(min(maxQuantity, current + add))"
            } else if let abs = absolute {
                inputBuffer = "\(abs)"
            }
        } label: {
            Text(verbatim: label.normalizedEnglishDigits)
                .font(AdminType.captionBold)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(AdminSurface.surface, in: Capsule())
                .foregroundColor(AdminSurface.primaryText)
                .overlay(Capsule().stroke(AdminSurface.hairline))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - 🐾 Live Pet Veterinary Quarantine & Clinical Disposition Deck

private struct LivePetVeterinaryQuarantineDeckView: View {
    let item: PetAccessory
    let branchId: String
    let branchRecord: PPBranchInventory?
    let availableQty: Int
    let quarantineQty: Int
    let onDismiss: () -> Void
    let onResolved: (() -> Void)?

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var quarantinedUnits: [PPLivePetInventoryUnit] = []
    @State private var selectedUnit: PPLivePetInventoryUnit? = nil
    @State private var isLoadingUnits: Bool = true
    @State private var errorMessage: String? = nil

    @State private var selectedDecision: LivePetClinicalDecision = .releaseToHealthy
    @State private var selectedReasonCode: String = "clinical_recovery"
    @State private var clinicalNotes: String = ""
    @State private var isSubmitting: Bool = false

    private var isPad: Bool {
        UIDevice.current.userInterfaceIdiom == .pad && horizontalSizeClass != .compact
    }

    private var onHandQty: Int {
        branchRecord?.onHandQuantity ?? (availableQty + quarantineQty)
    }

    private var canReleaseQuarantine: Bool {
        let staff = PPStaffAuth.shared().cachedCurrentStaff
        let isManager = staff?.hasPermission("stock.manage") ?? false
        let isQuarantineRelease = staff?.hasPermission("stock.quarantine.release") ?? false
        return isManager || isQuarantineRelease
    }

    private var isSubmitDisabled: Bool {
        if isSubmitting { return true }
        if selectedDecision == .releaseToHealthy && !canReleaseQuarantine { return true }
        if item.inventoryMode == "individual" && selectedUnit == nil && !quarantinedUnits.isEmpty { return true }
        return false
    }

    var body: some View {
        Group {
            if isPad {
                iPadLivePetDeck
            } else {
                iPhoneLivePetDeck
            }
        }
        .task {
            await loadQuarantinedUnits()
        }
    }

    // MARK: - 📱 iPhone Live Pet Deck

    private var iPhoneLivePetDeck: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: AdminSpacing.md) {
                LivePetSpecimenHeroCard(item: item, onHandQty: onHandQty)
                LivePetTelemetryRadar(quarantineQty: quarantineQty, availableQty: availableQty)

                if let errorMessage = errorMessage {
                    AdminErrorBanner(message: errorMessage) {
                        self.errorMessage = nil
                    }
                }

                quarantinedUnitsSection
                decisionsSection
                reasonsSection
                vetNotesSection

                Spacer().frame(height: 100)
            }
            .padding(.horizontal, AdminSpacing.screenMargin)
            .padding(.top, AdminSpacing.sm)
        }
        .clipped()
        .safeAreaInset(edge: .bottom) {
            LivePetFloatingCommandDock(
                decision: selectedDecision,
                selectedUnit: selectedUnit,
                isDisabled: isSubmitDisabled,
                isSubmitting: isSubmitting,
                onSubmit: promptConfirmation
            )
        }
    }

    // MARK: - 🖥️ iPad Live Pet Dual-Pane Deck

    private var iPadLivePetDeck: some View {
        HStack(spacing: 0) {
            // Leading Pane: Specimen Radar & Quarantined Units (Width: 380)
            VStack(spacing: 0) {
                ScrollView(showsIndicators: false) {
                    VStack(spacing: AdminSpacing.md) {
                        LivePetSpecimenHeroCard(item: item, onHandQty: onHandQty, isWidescreen: true)
                        LivePetTelemetryRadar(quarantineQty: quarantineQty, availableQty: availableQty)
                        quarantinedUnitsSection
                    }
                    .padding(AdminSpacing.lg)
                }
                .clipped()
            }
            .frame(width: 380)
            .background(AdminSurface.surface)
            .overlay(
                Rectangle()
                    .fill(AdminSurface.hairline)
                    .frame(width: 1),
                alignment: .trailing
            )

            // Trailing Pane: Clinical Decision & Execution
            VStack(spacing: 0) {
                ScrollView(showsIndicators: false) {
                    VStack(spacing: AdminSpacing.lg) {
                        if let errorMessage = errorMessage {
                            AdminErrorBanner(message: errorMessage) {
                                self.errorMessage = nil
                            }
                        }

                        decisionsSection
                        reasonsSection
                        vetNotesSection
                    }
                    .padding(AdminSpacing.lg)
                }
                .clipped()

                Divider().background(AdminSurface.hairline)

                LivePetFloatingCommandDock(
                    decision: selectedDecision,
                    selectedUnit: selectedUnit,
                    isDisabled: isSubmitDisabled,
                    isSubmitting: isSubmitting,
                    onSubmit: promptConfirmation
                )
                .padding(.top, 10)
            }
        }
    }

    // MARK: - Quarantined Units Section

    private var quarantinedUnitsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(Language.get("LivePet_Quarantined_Units_Header", alter: "الحالات المعزولة قيد الفحص الطبي"))
                    .font(AdminType.captionBold)
                    .foregroundColor(AdminSurface.secondaryText)

                Spacer()

                if isLoadingUnits {
                    ProgressView()
                        .scaleEffect(0.7)
                } else {
                    Text(verbatim: "\(quarantinedUnits.count)".normalizedEnglishDigits)
                        .font(AdminType.captionBold)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(Color(red: 147/255, green: 51/255, blue: 234/255).opacity(0.12), in: Capsule())
                        .foregroundColor(Color(red: 147/255, green: 51/255, blue: 234/255))
                }
            }

            if quarantinedUnits.isEmpty && !isLoadingUnits {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.shield.fill")
                        .font(.system(size: 16))
                        .foregroundColor(Color(red: 16/255, green: 185/255, blue: 129/255))
                    Text(Language.get("LivePet_No_Quarantined_Units", alter: "لا توجد حيوانات قيد العزل الطبي حالياً"))
                        .font(AdminType.caption)
                        .foregroundColor(AdminSurface.secondaryText)
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(AdminSurface.hairline, lineWidth: 1)
                )
            } else {
                VStack(spacing: 8) {
                    ForEach(quarantinedUnits) { unit in
                        quarantinedUnitCard(unit)
                    }
                }
            }
        }
    }

    private func quarantinedUnitCard(_ unit: PPLivePetInventoryUnit) -> some View {
        let isSelected = selectedUnit?.id == unit.id
        return Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            withAnimation(.spring(response: 0.28, dampingFraction: 0.8)) {
                selectedUnit = unit
            }
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    // Ring Tag
                    HStack(spacing: 4) {
                        Image(systemName: "tag.fill")
                            .font(.system(size: 10, weight: .bold))
                        Text(unit.ringTag.isEmpty ? String(unit.id.prefix(6)).uppercased() : unit.ringTag)
                            .font(Font.system(size: 13, weight: .bold, design: .monospaced))
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color(red: 147/255, green: 51/255, blue: 234/255).opacity(0.14), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .foregroundColor(Color(red: 147/255, green: 51/255, blue: 234/255))

                    // Status Pill
                    HStack(spacing: 4) {
                        Circle()
                            .fill(Color(red: 147/255, green: 51/255, blue: 234/255))
                            .frame(width: 6, height: 6)
                        Text(Language.get("LivePet_Status_UnderInspection", alter: "قيد الفحص والتقييم"))
                            .font(AdminType.caption2)
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(Color(red: 147/255, green: 51/255, blue: 234/255).opacity(0.10), in: Capsule())
                    .foregroundColor(Color(red: 147/255, green: 51/255, blue: 234/255))

                    Spacer()

                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 18))
                        .foregroundColor(isSelected ? Color(red: 147/255, green: 51/255, blue: 234/255) : AdminSurface.control)
                }

                // If from return case (e.g. Canary CR4)
                if !unit.returnCaseId.isEmpty || unit.quarantineReason == "LIVE_ANIMAL_RETURN" {
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.uturn.backward.circle.fill")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundColor(Color(red: 147/255, green: 51/255, blue: 234/255))
                            Text(Language.get("LivePet_Custody_UnderInspection", alter: "الحيوان مسترجع وقيد الفحص والتقييم"))
                                .font(AdminType.captionBold)
                                .foregroundColor(AdminSurface.primaryText)
                        }

                        if !unit.returnCaseId.isEmpty {
                            Text(verbatim: String(format: Language.get("LivePet_ReturnCase_Ref", alter: "ملف الاسترجاع: %@"), unit.returnCaseId))
                                .font(Font.system(size: 11, weight: .semibold, design: .monospaced))
                                .foregroundColor(Color(red: 147/255, green: 51/255, blue: 234/255))
                        }

                        if !unit.returnReason.isEmpty {
                            Text(verbatim: String(format: Language.get("LivePet_ReturnReason_Label", alter: "سبب الإرجاع: %@"), unit.returnReason))
                                .font(AdminType.caption2)
                                .foregroundColor(AdminSurface.secondaryText)
                        }
                    }
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(red: 147/255, green: 51/255, blue: 234/255).opacity(0.08), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
            }
            .padding(12)
            .background(isSelected ? Color(red: 147/255, green: 51/255, blue: 234/255).opacity(0.04) : AdminSurface.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(isSelected ? Color(red: 147/255, green: 51/255, blue: 234/255) : AdminSurface.hairline, lineWidth: isSelected ? 1.5 : 1)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Decisions Section

    private var decisionsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(Language.get("LivePet_Clinical_Decision_Header", alter: "القرار والإجراء البيطري"))
                .font(AdminType.captionBold)
                .foregroundColor(AdminSurface.secondaryText)

            VStack(spacing: 8) {
                ForEach(LivePetClinicalDecision.allCases) { decision in
                    LivePetClinicalActionCard(
                        decision: decision,
                        isSelected: selectedDecision == decision,
                        canRelease: canReleaseQuarantine,
                        onSelect: {
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            withAnimation(.spring(response: 0.28, dampingFraction: 0.8)) {
                                selectedDecision = decision
                                if let first = currentReasons.first {
                                    selectedReasonCode = first.code
                                }
                            }
                        }
                    )
                }
            }
        }
    }

    // MARK: - Reasons Section

    private var reasonsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(Language.get("LivePet_Clinical_Reason_Header", alter: "المسوغ الطبي والتشخيص السريري"))
                .font(AdminType.captionBold)
                .foregroundColor(AdminSurface.secondaryText)

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: 8)], spacing: 8) {
                ForEach(currentReasons) { reason in
                    Button {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        withAnimation(.spring(response: 0.24, dampingFraction: 0.8)) {
                            selectedReasonCode = reason.code
                        }
                    } label: {
                        HStack(spacing: 6) {
                            if selectedReasonCode == reason.code {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.system(size: 11, weight: .bold))
                            }
                            Text(reason.label)
                                .font(AdminType.captionBold)
                                .lineLimit(1)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .frame(maxWidth: .infinity)
                        .background(
                            selectedReasonCode == reason.code
                                ? selectedDecision.tintColor
                                : AdminSurface.surface
                        )
                        .foregroundColor(
                            selectedReasonCode == reason.code
                                ? .white
                                : AdminSurface.primaryText
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .strokeBorder(
                                    selectedReasonCode == reason.code
                                        ? Color.clear
                                        : AdminSurface.hairline,
                                    lineWidth: 1
                                )
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: - Vet Notes Section

    private var vetNotesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(Language.get("LivePet_VetNotes_Title", alter: "تقرير الفحص السريري والملاحظات البيطرية"))
                .font(AdminType.captionBold)
                .foregroundColor(AdminSurface.secondaryText)

            // Quick clinical tags
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(quickClinicalTags, id: \.self) { tag in
                        Button {
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            if clinicalNotes.isEmpty {
                                clinicalNotes = tag
                            } else if !clinicalNotes.contains(tag) {
                                clinicalNotes += " • " + tag
                            }
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "plus.circle.fill")
                                    .font(.system(size: 10))
                            Text(tag)
                                .font(AdminType.caption2)
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(AdminSurface.control, in: Capsule())
                            .foregroundColor(AdminSurface.primaryText)
                            .overlay(Capsule().strokeBorder(AdminSurface.hairline, lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            // Notes Text Area
            ZStack(alignment: .topLeading) {
                if clinicalNotes.isEmpty {
                    Text(Language.get("LivePet_VetNotes_Placeholder", alter: "سجل الفحص السريري: درجة الحرارة، التنفس، فحص الريش/الفراء، الأدوية الموصوفة وتوصية الطبيب..."))
                        .font(AdminType.caption)
                        .foregroundColor(AdminSurface.secondaryText.opacity(0.7))
                        .padding(10)
                }

                TextEditor(text: $clinicalNotes)
                    .font(AdminType.callout)
                    .frame(minHeight: 70)
                    .padding(6)
                    .background(Color.clear)
            }
            .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(AdminSurface.hairline, lineWidth: 1)
            )
        }
    }

    // MARK: - Helpers & Data Handlers

    private var quickClinicalTags: [String] {
        [
            Language.get("LivePet_Tag_RespiratoryClear", alter: "فحص تنفسي سليم"),
            Language.get("LivePet_Tag_ActiveNormal", alter: "نشاط وحركة طبيعية"),
            Language.get("LivePet_Tag_GoodAppetite", alter: "شهية جيدة"),
            Language.get("LivePet_Tag_UnderAntibiotic", alter: "تحت المضاد الحيوي"),
            Language.get("LivePet_Tag_Lethargic", alter: "خمول بحاجة راحة")
        ]
    }

    private var selectedReasonLabel: String {
        currentReasons.first { $0.code == selectedReasonCode }?.label ?? selectedReasonCode
    }

    private var currentReasons: [LivePetReasonItem] {
        switch selectedDecision {
        case .releaseToHealthy:
            return [
                LivePetReasonItem(code: "clinical_recovery", label: Language.get("LivePet_Reason_Recovery", alter: "تعافي سريري واكتمال العلاج")),
                LivePetReasonItem(code: "post_return_cleared", label: Language.get("LivePet_Reason_ReturnCleared", alter: "سلامة الفحص الطبي بعد الاسترجاع")),
                LivePetReasonItem(code: "quarantine_completed", label: Language.get("LivePet_Reason_QuarantineDone", alter: "انتهاء فترة الملاحظة الوقائية")),
                LivePetReasonItem(code: "vet_clearance_certified", label: Language.get("LivePet_Reason_VetClearance", alter: "شهادة فحص واعتماد طبيب بيطري"))
            ]
        case .recordMortality:
            return [
                LivePetReasonItem(code: "sudden_mortality", label: Language.get("LivePet_Reason_SuddenDeath", alter: "نفوق مفاجئ / هبوط حاد")),
                LivePetReasonItem(code: "infectious_disease", label: Language.get("LivePet_Reason_Infectious", alter: "مرض معدي وتدهور سريري")),
                LivePetReasonItem(code: "post_return_complications", label: Language.get("LivePet_Reason_ReturnComp", alter: "مضاعفات صحية بعد الاسترجاع")),
                LivePetReasonItem(code: "heat_respiratory_stress", label: Language.get("LivePet_Reason_Stress", alter: "إجهاد حراري أو تنفسي")),
                LivePetReasonItem(code: "age_physiological", label: Language.get("LivePet_Reason_Physiological", alter: "أسباب طبيعية وفسيولوجية"))
            ]
        case .extendIsolation:
            return [
                LivePetReasonItem(code: "under_active_treatment", label: Language.get("LivePet_Reason_UnderTreatment", alter: "تحت العلاج والمضادات الحيوية")),
                LivePetReasonItem(code: "awaiting_lab_results", label: Language.get("LivePet_Reason_AwaitingLabs", alter: "بانتظار نتائج الفحوصات والتحاليل")),
                LivePetReasonItem(code: "observation_period", label: Language.get("LivePet_Reason_ObsPeriod", alter: "استكمال فترة الحجر والملاحظة"))
            ]
        }
    }

    private func loadQuarantinedUnits() async {
        isLoadingUnits = true
        do {
            let allUnits = try await PPLivePetInventoryService.listUnits(
                productID: item.accessoryID,
                includeHistory: true,
                includeReservations: false
            )
            let filtered = allUnits.filter { $0.isUnderInspection || $0.status.uppercased() == "QUARANTINED" }.sorted()
            await MainActor.run {
                self.quarantinedUnits = filtered
                self.selectedUnit = filtered.first
                self.isLoadingUnits = false
            }
        } catch {
            await MainActor.run {
                self.isLoadingUnits = false
            }
        }
    }

    private func promptConfirmation() {
        let confirmTitle = selectedDecision == .recordMortality
            ? Language.get("LivePet_Action_ConfirmMortality", alter: "إقرار وتسجيل النفوق رسمياً")
            : Language.get("Confirm", alter: "تأكيد التنفيذ")
        let cancelTitle = Language.get("Cancel", alter: "إلغاء")
        let alertTitle = selectedDecision.title

        let alertSubtitle: String = {
            let specimenLabel = selectedUnit.map { "(\($0.ringTag.isEmpty ? String($0.id.prefix(6)) : $0.ringTag))" } ?? ""
            switch selectedDecision {
            case .releaseToHealthy:
                return "\(Language.get("LivePet_Confirm_Release_Desc", alter: "هل أنت متأكد من إنهاء الحجر البيطري وإعادة الحيوان")) \(specimenLabel) \(Language.get("LivePet_Confirm_Release_End", alter: "إلى الرصيد المتاح للبيع؟"))"
            case .recordMortality:
                return "\(Language.get("LivePet_Confirm_Mortality_Desc", alter: "تحذير: سيتم تسجيل نفوق الحيوان")) \(specimenLabel) \(Language.get("LivePet_Confirm_Mortality_End", alter: "وإسقاطه نهائياً من سجلات العهدة الحية بناءً على التشخيص البيطري."))"
            case .extendIsolation:
                return "\(Language.get("LivePet_Confirm_Extend_Desc", alter: "سيتم حفظ تقرير الكشف السريري وتثبيت الحيوان في قفص العزل والملاحظة."))"
            }
        }()

        let icon = UIImage(systemName: selectedDecision.iconName)

        PPAlertHelper.showConfirmation(
            in: nil,
            title: alertTitle,
            subtitle: alertSubtitle,
            confirmButton: confirmTitle,
            cancelButton: cancelTitle,
            icon: icon,
            confirmBlock: { _, didConfirm in
                guard didConfirm else { return }
                executeDecision()
            },
            cancelBlock: nil
        )
    }

    private func executeDecision() {
        guard !isSubmitting else { return }
        isSubmitting = true
        errorMessage = nil

        Task {
            do {
                let commandId = PPLivePetInventoryService.commandID("live-quarantine")
                switch selectedDecision {
                case .releaseToHealthy:
                    if let unit = selectedUnit {
                        var payload: [String: Any] = [
                            "unitId": unit.id,
                            "reason": selectedReasonLabel,
                            "notes": clinicalNotes
                        ]
                        if !unit.returnCaseId.isEmpty {
                            payload["returnCaseId"] = unit.returnCaseId
                        }
                        _ = try await PPLivePetInventoryService.callInventory(
                            action: "release_quarantine",
                            productID: item.accessoryID,
                            commandID: commandId,
                            payload: payload
                        )
                    } else {
                        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                            PPBranchInventoryService.shared.resolveDisposition(
                                productId: item.accessoryID,
                                branchId: branchId,
                                quantity: 1,
                                action: "move",
                                fromBucket: "quarantine",
                                toBucket: "available",
                                reasonCode: selectedReasonCode,
                                notes: clinicalNotes
                            ) { result in
                                switch result {
                                case .success: continuation.resume()
                                case .failure(let err): continuation.resume(throwing: err)
                                }
                            }
                        }
                    }

                case .recordMortality:
                    if let unit = selectedUnit {
                        let payload: [String: Any] = [
                            "unitId": unit.id,
                            "reason": selectedReasonLabel,
                            "causeCode": selectedReasonCode,
                            "notes": clinicalNotes,
                            "veterinaryReference": "VET-QUARANTINE",
                            "attachmentURLs": []
                        ]
                        _ = try await PPLivePetInventoryService.callInventory(
                            action: "record_mortality",
                            productID: item.accessoryID,
                            commandID: commandId,
                            payload: payload
                        )
                    } else {
                        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                            PPBranchInventoryService.shared.resolveDisposition(
                                productId: item.accessoryID,
                                branchId: branchId,
                                quantity: 1,
                                action: "write_off",
                                fromBucket: "quarantine",
                                reasonCode: selectedReasonCode,
                                notes: clinicalNotes
                            ) { result in
                                switch result {
                                case .success: continuation.resume()
                                case .failure(let err): continuation.resume(throwing: err)
                                }
                            }
                        }
                    }

                case .extendIsolation:
                    if let unit = selectedUnit {
                        let docRef = Firestore.firestore().collection("petAccessories").document(item.accessoryID).collection("inventoryUnits").document(unit.id)
                        try await docRef.setData([
                            "quarantineNotes": clinicalNotes,
                            "lastClinicalCheckAt": FieldValue.serverTimestamp(),
                            "clinicalStatus": selectedReasonCode
                        ], merge: true)
                    }
                }

                await MainActor.run {
                    isSubmitting = false
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                    onResolved?()
                    onDismiss()
                }
            } catch {
                await MainActor.run {
                    isSubmitting = false
                    UINotificationFeedbackGenerator().notificationOccurred(.error)
                    errorMessage = PPLivePetInventoryService.localizedMessage(for: error)
                }
            }
        }
    }
}

// MARK: - 🐾 Live Pet Subcomponents

private struct LivePetSpecimenHeroCard: View {
    let item: PetAccessory
    let onHandQty: Int
    var isWidescreen: Bool = false

    private var displayName: String {
        if !Language.isRTL(), let nameEn = item.nameEn?.trimmingCharacters(in: .whitespacesAndNewlines), !nameEn.isEmpty {
            return nameEn
        }
        return item.name
    }

    var body: some View {
        VStack(spacing: 12) {
            HStack(alignment: .top, spacing: 14) {
                // Species Image
                ZStack {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(AdminSurface.control)

                    if let first = item.imageURLsArray.first, !first.isEmpty, let url = URL(string: first) {
                        AsyncImage(url: url) { img in
                            img.resizable().scaledToFill()
                        } placeholder: {
                            Image(systemName: "pawprint.fill")
                                .font(.system(size: 24))
                                .foregroundColor(Color(red: 147/255, green: 51/255, blue: 234/255).opacity(0.6))
                        }
                    } else {
                        Image(systemName: "pawprint.fill")
                            .font(.system(size: 24))
                            .foregroundColor(Color(red: 147/255, green: 51/255, blue: 234/255).opacity(0.6))
                    }
                }
                .frame(width: isWidescreen ? 80 : 68, height: isWidescreen ? 80 : 68)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(Color(red: 147/255, green: 51/255, blue: 234/255).opacity(0.3), lineWidth: 1)
                )

                // Identity Details
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        // Kind Badge
                        let categoryName = item.category ?? item.accessoryCategoryName ?? Language.get("LivePet_Species", alter: "حيوان حي")
                        Text(categoryName)
                            .font(AdminType.caption2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(AdminSurface.control, in: Capsule())
                            .foregroundColor(AdminSurface.secondaryText)

                        // Live Pet Veterinary Badge
                        HStack(spacing: 3) {
                            Image(systemName: "stethoscope")
                                .font(.system(size: 9, weight: .bold))
                            Text(Language.get("LivePet_Quarantine_Badge", alter: "عزل بيطري"))
                                .font(.system(size: 9, weight: .bold))
                        }
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color(red: 147/255, green: 51/255, blue: 234/255).opacity(0.12), in: Capsule())
                        .foregroundColor(Color(red: 147/255, green: 51/255, blue: 234/255))
                    }

                    Text(displayName)
                        .font(AdminType.headlineBold)
                        .foregroundColor(AdminSurface.primaryText)
                        .lineLimit(2)

                    // Tracking Mode Pill
                    HStack(spacing: 4) {
                        Image(systemName: item.inventoryMode == "individual" ? "tag.fill" : "square.stack.3d.up.fill")
                            .font(.system(size: 10, weight: .bold))
                        Text(item.inventoryMode == "individual" ? Language.get("Live_Mode_Individual", alter: "تتبع فردي بالرأس (حجل/شريحة)") : Language.get("Live_Mode_Group", alter: "إدارة كمية بالمجموعة"))
                            .font(AdminType.caption2)
                    }
                    .foregroundColor(AdminSurface.secondaryText)
                }

                Spacer()
            }
        }
        .padding(14)
        .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: AdminRadius.card))
        .overlay(
            RoundedRectangle(cornerRadius: AdminRadius.card)
                .strokeBorder(AdminSurface.hairline, lineWidth: 1)
        )
    }
}

private struct LivePetTelemetryRadar: View {
    let quarantineQty: Int
    let availableQty: Int

    var body: some View {
        HStack(spacing: 12) {
            // Quarantine & Medical Isolation Card
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Image(systemName: "cross.case.fill")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(Color(red: 147/255, green: 51/255, blue: 234/255))
                    Spacer()
                    Text(verbatim: "\(quarantineQty)".normalizedEnglishDigits)
                        .font(Font.system(size: 22, weight: .bold, design: .rounded))
                        .foregroundColor(Color(red: 147/255, green: 51/255, blue: 234/255))
                }

                Text(Language.get("LivePet_Status_Quarantined", alter: "في الحجر والعزل"))
                    .font(AdminType.captionBold)
                    .foregroundColor(AdminSurface.primaryText)

                Text(Language.get("LivePet_Status_UnderInspection", alter: "قيد الفحص والتقييم"))
                    .font(AdminType.caption2)
                    .foregroundColor(AdminSurface.secondaryText)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(red: 147/255, green: 51/255, blue: 234/255).opacity(0.08), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(Color(red: 147/255, green: 51/255, blue: 234/255).opacity(0.25), lineWidth: 1)
            )

            // Healthy & Ready For Sale Card
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(Color(red: 16/255, green: 185/255, blue: 129/255))
                    Spacer()
                    Text(verbatim: "\(availableQty)".normalizedEnglishDigits)
                        .font(Font.system(size: 22, weight: .bold, design: .rounded))
                        .foregroundColor(Color(red: 16/255, green: 185/255, blue: 129/255))
                }

                Text(Language.get("InStock", alter: "سليم ومتاح للبيع"))
                    .font(AdminType.captionBold)
                    .foregroundColor(AdminSurface.primaryText)

                Text(Language.get("LivePet_Ready_For_Sale", alter: "جاهز للصرف والتسليم"))
                    .font(AdminType.caption2)
                    .foregroundColor(AdminSurface.secondaryText)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(red: 16/255, green: 185/255, blue: 129/255).opacity(0.08), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(Color(red: 16/255, green: 185/255, blue: 129/255).opacity(0.25), lineWidth: 1)
            )
        }
    }
}

private struct LivePetClinicalActionCard: View {
    let decision: LivePetClinicalDecision
    let isSelected: Bool
    let canRelease: Bool
    let onSelect: () -> Void

    private var isBlocked: Bool {
        decision == .releaseToHealthy && !canRelease
    }

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 12) {
                Image(systemName: decision.iconName)
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(decision.tintColor)
                    .frame(width: 38, height: 38)
                    .background(decision.tintColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 10, style: .continuous))

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(decision.title)
                            .font(AdminType.calloutBold)
                            .foregroundColor(AdminSurface.primaryText)

                        Text(decision.badgeText)
                            .font(.system(size: 9, weight: .bold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(decision.tintColor.opacity(0.12), in: Capsule())
                            .foregroundColor(decision.tintColor)

                        if isBlocked {
                            HStack(spacing: 3) {
                                Image(systemName: "lock.fill")
                                    .font(.system(size: 8))
                                Text(Language.get("Quarantine_Perm_Locked", alter: "صلاحية مقيدة"))
                                    .font(.system(size: 9, weight: .bold))
                            }
                            .foregroundColor(.amber)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.amber.opacity(0.12), in: Capsule())
                        }
                    }

                    Text(decision.subtitle)
                        .font(AdminType.caption2)
                        .foregroundColor(AdminSurface.secondaryText)
                        .lineLimit(2)
                }

                Spacer()

                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 20))
                    .foregroundColor(isSelected ? decision.tintColor : AdminSurface.control)
            }
            .padding(12)
            .background(isSelected ? decision.tintColor.opacity(0.06) : AdminSurface.surface, in: RoundedRectangle(cornerRadius: AdminRadius.card))
            .overlay(
                RoundedRectangle(cornerRadius: AdminRadius.card)
                    .strokeBorder(isSelected ? decision.tintColor : AdminSurface.hairline, lineWidth: isSelected ? 1.5 : 1)
            )
        }
        .buttonStyle(.plain)
    }
}

private struct LivePetFloatingCommandDock: View {
    let decision: LivePetClinicalDecision
    let selectedUnit: PPLivePetInventoryUnit?
    let isDisabled: Bool
    let isSubmitting: Bool
    let onSubmit: () -> Void

    var buttonTitle: String {
        switch decision {
        case .releaseToHealthy:
            return Language.get("LivePet_Action_ConfirmRelease", alter: "اعتماد الإفراج ونقل للرصيد المتاح")
        case .recordMortality:
            return Language.get("LivePet_Action_ConfirmMortality", alter: "إقرار وتسجيل النفوق رسمياً")
        case .extendIsolation:
            return Language.get("LivePet_Action_ConfirmExtend", alter: "حفظ تقرير الفحص وتمديد العزل")
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: AdminSpacing.md) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 4) {
                        Circle().fill(decision.tintColor).frame(width: 8, height: 8)
                        Text(decision.title)
                            .font(AdminType.captionBold)
                            .foregroundColor(AdminSurface.primaryText)
                            .lineLimit(1)
                    }

                    if let unit = selectedUnit {
                        Text(verbatim: "\(Language.get("LivePet_Ring", alter: "الحجل")): \(unit.ringTag.isEmpty ? String(unit.id.prefix(6)) : unit.ringTag)".normalizedEnglishDigits)
                            .font(Font.system(size: 13, weight: .bold, design: .monospaced))
                            .foregroundColor(decision.tintColor)
                    }
                }

                Spacer()

                Button(action: onSubmit) {
                    HStack(spacing: 8) {
                        if isSubmitting {
                            ProgressView().tint(.white)
                        } else {
                            Image(systemName: decision.iconName)
                                .font(.system(size: 14, weight: .bold))
                            Text(buttonTitle)
                                .font(AdminType.calloutBold)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                    .background(isDisabled ? AdminSurface.control : decision.tintColor, in: RoundedRectangle(cornerRadius: AdminRadius.card))
                    .foregroundColor(isDisabled ? AdminSurface.secondaryText : .white)
                }
                .disabled(isDisabled)
            }
            .padding(.horizontal, AdminSpacing.md)
            .padding(.vertical, AdminSpacing.sm)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18))
            .overlay(
                RoundedRectangle(cornerRadius: 18)
                    .strokeBorder(AdminSurface.hairline, lineWidth: 1)
            )
            .padding(.horizontal, AdminSpacing.screenMargin)
            .padding(.bottom, 8)
        }
    }
}

private struct LivePetReasonItem: Identifiable {
    var id: String { code }
    let code: String
    let label: String
}

private enum LivePetClinicalDecision: String, CaseIterable, Identifiable {
    case releaseToHealthy = "release"
    case recordMortality = "mortality"
    case extendIsolation = "extend"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .releaseToHealthy:
            return Language.get("LivePet_Decision_Release", alter: "إفراج للمخزون السليم (جاهز للبيع)")
        case .recordMortality:
            return Language.get("LivePet_Decision_Mortality", alter: "إقرار وتسجيل نفوق الحيوان")
        case .extendIsolation:
            return Language.get("LivePet_Decision_Extend", alter: "تمديد العزل والملاحظة السريرية")
        }
    }

    var subtitle: String {
        switch self {
        case .releaseToHealthy:
            return Language.get("LivePet_Decision_Release_Sub", alter: "اجتياز الفحص الطبي السريري والتأكد من سلامة الحيوان وإعادته للبيع")
        case .recordMortality:
            return Language.get("LivePet_Decision_Mortality_Sub", alter: "توثيق وفاة الحيوان وتحديد السبب الطبي البيطري وإسقاط الرأس رسمياً")
        case .extendIsolation:
            return Language.get("LivePet_Decision_Extend_Sub", alter: "إبقاء الحيوان في قفص العزل الطبي ومتابعة العلاج والفحوصات اليومية")
        }
    }

    var badgeText: String {
        switch self {
        case .releaseToHealthy: return Language.get("Healthy_Certified", alter: "سليم ومعافى")
        case .recordMortality: return Language.get("Death_Certificate", alter: "شهادة وفاة")
        case .extendIsolation: return Language.get("Clinical_Observation", alter: "متابعة سريرية")
        }
    }

    var iconName: String {
        switch self {
        case .releaseToHealthy: return "checkmark.seal.fill"
        case .recordMortality: return "heart.slash.fill"
        case .extendIsolation: return "cross.case.fill"
        }
    }

    var tintColor: Color {
        switch self {
        case .releaseToHealthy: return Color(red: 16/255, green: 185/255, blue: 129/255)
        case .recordMortality: return Color(red: 225/255, green: 29/255, blue: 72/255)
        case .extendIsolation: return Color(red: 147/255, green: 51/255, blue: 234/255)
        }
    }
}

