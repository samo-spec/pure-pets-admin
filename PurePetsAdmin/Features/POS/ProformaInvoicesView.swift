import SwiftUI
import UIKit

/// A native document workspace inside the existing Admin route/session owner.
@MainActor
struct AdminProformaInvoicesView: View {
    let session: AdminSession
    var onDismiss: (() -> Void)? = nil
    @ObservedObject private var branches = BranchContextStore.shared
    @StateObject private var store: ProformaInvoiceStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var customerPicker = false
    @State private var catalogPicker = false
    @State private var conversionSheet = false
    @State private var preview: ProformaPreviewDocument?
    @State private var pendingShare: ProformaPreviewDocument?
    @State private var shareDocument: PPProformaPDFDocument?
    @State private var localError: String?
    @State private var discardAction: ProformaDiscardAction?
    @State private var cancellationConfirmation = false
    @State private var actualReceipt: POSCompletedReceipt?
    @State private var actualReceiptLoading = false
    @State private var filter = "all"

    private var canWrite: Bool { session.hasPermission("pos.sell") }
    private var activeBranchID: String { branches.activeBranch?.branchID ?? session.branchId ?? "" }
    init(session: AdminSession, onDismiss: (() -> Void)? = nil) {
        self.session = session; self.onDismiss = onDismiss
        _store = StateObject(wrappedValue: ProformaInvoiceStore(actorUID: session.uid))
    }

    private var editable: Bool { canWrite && !store.isLocked && !store.isLoading && (store.selected?.status.isEditable ?? true) }
    private var visibleInvoices: [ProformaInvoice] {
        filter == "all" ? store.invoices : store.invoices.filter { $0.status.rawValue == filter }
    }

    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                header
                if !session.hasAnyPermission(["pos.view", "pos.sell"]) {
                    stateMessage("Proforma_Error_Denied", symbol: "lock", detail: "Proforma_Authority")
                } else if geometry.size.width >= 760 && !typeSize.isAccessibilitySize {
                    HStack(alignment: .top, spacing: 0) {
                        invoiceDirectory.frame(width: min(340, geometry.size.width * 0.36))
                        Divider()
                        documentWorkspace.frame(maxWidth: .infinity)
                    }
                } else if store.hasSelection {
                    documentWorkspace
                } else { invoiceDirectory }
            }
            .background(AdminSurface.background)
        }
        .environment(\.layoutDirection, Language.isRTL() ? .rightToLeft : .leftToRight)
        .environment(\.locale, Locale(identifier: Language.isRTL() ? "ar" : "en"))
        .interactiveDismissDisabled(store.hasUnsavedChanges || store.isLocked)
        .background(ProformaNavigationGuard(blocked: store.hasUnsavedChanges || store.isLocked))
        .task(id: activeBranchID) {
            guard session.hasAnyPermission(["pos.view", "pos.sell"]) else { return }
            await store.load(branchId: activeBranchID)
        }
        .sheet(isPresented: $customerPicker) {
            POSCustomerPickerSheet(currentSelected: store.draft?.customer?.pickerRecord,
                                   canCreateCustomer: canWrite, purpose: .proformaInvoice) { record in
                store.draft?.customer = ProformaCustomer(record); customerPicker = false
            }
        }
        .sheet(isPresented: $catalogPicker) {
            ProformaCatalogSheet(store: store, currency: store.draft?.currency ?? "")
        }
        .sheet(isPresented: $conversionSheet) {
            if let invoice = store.selected {
                ProformaConversionSheet(invoice: invoice, store: store)
                    .environment(\.layoutDirection, Language.isRTL() ? .rightToLeft : .leftToRight)
            }
        }
        .sheet(item: $preview, onDismiss: {
            if let document = pendingShare {
                pendingShare = nil
                do { shareDocument = try PPProformaPDFDocument(data: document.data, number: document.number) }
                catch { localError = error.localizedDescription }
            }
        }) { document in
            NavigationStack {
                PPProformaPDFPreview(data: document.data)
                    .navigationTitle(document.number)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button(pf("Proforma_Close")) { preview = nil }
                        }
                        ToolbarItem(placement: .primaryAction) {
                            Button(pf("Proforma_Share"), systemImage: "square.and.arrow.up") {
                                pendingShare = document; preview = nil
                            }
                        }
                    }
            }
            .environment(\.layoutDirection, Language.isRTL() ? .rightToLeft : .leftToRight)
        }
        .sheet(item: $shareDocument) { document in PPProformaPDFShareSheet(document: document) }
        .sheet(item: $actualReceipt) { receipt in POSCompletedReceiptSheet(receipt: receipt) }
        .confirmationDialog(pf("Proforma_Discard_Title"), isPresented: Binding(
            get: { discardAction != nil }, set: { if !$0 { discardAction = nil } }
        ), titleVisibility: .visible) {
            Button(pf("Proforma_Discard"), role: .destructive) {
                let action = discardAction; discardAction = nil; store.clearSelection()
                switch action {
                case .close: close()
                case .create: store.createDraft()
                case .open(let invoice): Task { await store.open(invoice) }
                case .directory, .none: Task { await store.load(branchId: activeBranchID, force: true) }
                }
            }
            Button(pf("Proforma_KeepEditing"), role: .cancel) { discardAction = nil }
        } message: { Text(pf("Proforma_Discard_Message")) }
        .confirmationDialog(pf("Proforma_CancelInvoice_Title"), isPresented: $cancellationConfirmation, titleVisibility: .visible) {
            Button(pf("Proforma_CancelInvoice"), role: .destructive) { Task { await store.perform("cancel") } }
            Button(pf("Proforma_KeepInvoice"), role: .cancel) {}
        } message: { Text(pf("Proforma_CancelInvoice_Message")) }
        .alert(pf("Proforma_Error_Title"), isPresented: Binding(get: { localError != nil }, set: { if !$0 { localError = nil } })) {
            Button(pf("Proforma_Close"), role: .cancel) { localError = nil }
        } message: { Text(localError ?? "") }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            Button {
                guard !store.isLocked else { return }
                if store.hasUnsavedChanges { discardAction = .close } else { close() }
            } label: {
                Image(systemName: "chevron.backward").font(.system(size: 19, weight: .semibold))
                    .frame(width: 44, height: 44).background(AdminSurface.backgroundSecondary, in: RoundedRectangle(cornerRadius: 14))
            }
            .accessibilityLabel(pf("Proforma_Back"))
            .disabled(store.isLocked)
            VStack(alignment: .leading, spacing: 1) {
                Text(pf("Proforma_Title")).font(AdminType.title2)
                Text(pf("Proforma_Subtitle")).font(AdminType.caption).foregroundStyle(AdminSurface.secondaryText)
            }
            Spacer(minLength: 0)
            if store.hasSelection {
                Button(pf("Proforma_Directory"), systemImage: "list.bullet") {
                    if store.hasUnsavedChanges { discardAction = .directory }
                    else { store.clearSelection(); Task { await store.load(branchId: activeBranchID) } }
                }
                .labelStyle(.iconOnly).frame(minWidth: 44, minHeight: 44).disabled(store.isLocked)
            }
        }
        .foregroundStyle(AdminSurface.primaryText)
        .padding(.horizontal, 20).padding(.vertical, 12)
        .background(AdminSurface.surface)
    }

    private var invoiceDirectory: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                PPAdminBranchSwitcherBar(style: .journal, horizontalPadding: 0)
                    .disabled(store.isLocked || store.hasUnsavedChanges)
                if activeBranchID.isEmpty {
                    stateMessage("Proforma_SelectBranch", symbol: "building.2", detail: "Proforma_SelectBranch_Detail")
                } else {
                    directoryControls
                    if store.confirmationPending { pendingPanel }
                    if let error = store.error { errorPanel(error) }
                    if store.isLoading && store.invoices.isEmpty {
                        ProgressView(pf("Proforma_Loading")).frame(maxWidth: .infinity, minHeight: 160)
                    } else if visibleInvoices.isEmpty {
                        stateMessage(filter == "all" ? "Proforma_Empty" : "Proforma_FilterEmpty", symbol: "doc.badge.plus", detail: "Proforma_Empty_Detail")
                    } else {
                        LazyVStack(spacing: 0) {
                            ForEach(visibleInvoices) { invoice in
                                Button {
                                    if store.hasUnsavedChanges { discardAction = .open(invoice) }
                                    else { Task { await store.open(invoice) } }
                                } label: { directoryRow(invoice) }
                                .buttonStyle(ProformaPressStyle()).disabled(store.isLocked || store.isLoading)
                                Divider().padding(.vertical, 8)
                            }
                        }
                    }
                    if store.nextCursor != nil {
                        Button(pf("Proforma_LoadMore")) { Task { await store.loadMore() } }
                            .frame(maxWidth: .infinity, minHeight: 44).disabled(store.isLoadingMore || store.isLocked)
                        if store.isLoadingMore { ProgressView().frame(maxWidth: .infinity) }
                    }
                }
            }
            .padding(20)
        }
        .refreshable { await store.load(branchId: activeBranchID) }
    }

    private var directoryControls: some View {
        VStack(alignment: .leading, spacing: 12) {
            if canWrite {
                Button {
                    if store.hasUnsavedChanges { discardAction = .create } else { store.createDraft() }
                } label: { Label(pf("Proforma_Create"), systemImage: "plus").frame(maxWidth: .infinity, minHeight: 48) }
                    .buttonStyle(ProformaPrimaryStyle()).disabled(store.context == nil || store.isLocked || store.isLoading)
            }
            Menu {
                Button(pf("Proforma_All")) { filter = "all" }
                ForEach([ProformaStatus.draft, .issued, .converted, .cancelled], id: \.rawValue) { status in
                    Button(status.title) { filter = status.rawValue }
                }
            } label: {
                HStack {
                    Text(filter == "all" ? pf("Proforma_All") : ProformaStatus(rawValue: filter)?.title ?? "")
                    Spacer(); Image(systemName: "chevron.down").font(.caption)
                }.font(AdminType.subheadlineBold).frame(minHeight: 44)
            }
        }
    }

    private func directoryRow(_ invoice: ProformaInvoice) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            ViewThatFits(in: .horizontal) {
                HStack { Text(invoice.number).font(AdminType.headline).environment(\.layoutDirection, .leftToRight); Spacer(); status(invoice) }
                VStack(alignment: .leading, spacing: 6) { Text(invoice.number).font(AdminType.headline).environment(\.layoutDirection, .leftToRight); status(invoice) }
            }
            Text(invoice.customer?.name.isEmpty == false ? invoice.customer!.name : pf("Proforma_NoCustomer"))
                .font(AdminType.subheadline).foregroundStyle(AdminSurface.secondaryText)
            Text(money(ProformaDecimal.minor(invoice.totals.totalMinor), currency: invoice.currency))
                .font(AdminType.title3).environment(\.layoutDirection, .leftToRight)
            Text(invoice.updatedAt, style: .date).font(AdminType.caption).foregroundStyle(AdminSurface.secondaryText)
        }
        .foregroundStyle(AdminSurface.primaryText)
        .padding(.vertical, 10).frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle()).accessibilityElement(children: .combine)
    }

    @ViewBuilder private var documentWorkspace: some View {
        if let draft = store.draft {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    documentMasthead(draft)
                    if store.confirmationPending { pendingPanel }
                    if let error = store.error { errorPanel(error) }
                    if draft.branchId != activeBranchID {
                        Label(pf("Proforma_BranchChanged"), systemImage: "building.2.crop.circle").font(AdminType.footnote).foregroundStyle(AdminSurface.amber)
                    }
                    customerSection(draft)
                    itemSection(draft)
                    termsSection(draft)
                    totalsSection(draft)
                    if store.selected?.status == .converted { convertedSection }
                    Text(pf("Proforma_Disclosure")).font(AdminType.footnote).foregroundStyle(AdminSurface.secondaryText).fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: 740, alignment: .leading).padding(24).frame(maxWidth: .infinity)
            }
            .scrollDismissesKeyboard(.interactively)
            .safeAreaInset(edge: .bottom) { documentActions }
        } else {
            stateMessage("Proforma_WorkspaceEmpty", symbol: "doc.text", detail: "Proforma_WorkspaceEmpty_Detail")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func documentMasthead(_ draft: ProformaDraft) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(pf("Proforma_DocumentLabel")).font(AdminType.captionBold).foregroundStyle(AdminSurface.primary)
            Text(draft.number ?? pf("Proforma_NewDraft")).font(AdminType.title)
                .environment(\.layoutDirection, draft.number == nil && Language.isRTL() ? .rightToLeft : .leftToRight)
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 12) {
                    Text(branchName(draft.branchId)).font(AdminType.subheadline)
                    if let selected = store.selected { status(selected) }
                }
                VStack(alignment: .leading, spacing: 8) {
                    Text(branchName(draft.branchId)).font(AdminType.subheadline)
                    if let selected = store.selected { status(selected) }
                }
            }
            if store.hasUnsavedChanges { Label(pf("Proforma_Unsaved"), systemImage: "pencil.circle").font(AdminType.caption).foregroundStyle(AdminSurface.amber) }
        }
    }

    private func customerSection(_ draft: ProformaDraft) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("Proforma_Customer")
            Button { customerPicker = true } label: {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "person.crop.circle").font(.system(size: 28, weight: .light)).foregroundStyle(AdminSurface.primary)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(draft.customer?.name ?? pf("Proforma_SelectCustomer")).font(AdminType.headline)
                        if let customer = draft.customer, !customer.phone.isEmpty {
                            Text(customer.phone).font(AdminType.subheadline).foregroundStyle(AdminSurface.secondaryText).environment(\.layoutDirection, .leftToRight)
                        }
                    }
                    Spacer(minLength: 0)
                    if editable { Image(systemName: "chevron.forward").font(.caption) }
                }
                .foregroundStyle(AdminSurface.primaryText).frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .padding(14).background(AdminSurface.backgroundSecondary, in: RoundedRectangle(cornerRadius: 14))
            }.buttonStyle(ProformaPressStyle()).disabled(!editable)
            if draft.customer != nil && editable {
                Button(pf("Proforma_RemoveCustomer")) { store.draft?.customer = nil }.font(AdminType.footnote).frame(minHeight: 44)
            }
        }
    }

    private func itemSection(_ draft: ProformaDraft) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                sectionTitle("Proforma_Items"); Spacer()
                if editable {
                    Button(pf("Proforma_AddItem"), systemImage: "plus") { catalogPicker = true }.font(AdminType.subheadlineBold).frame(minHeight: 44)
                }
            }
            if draft.items.isEmpty {
                Text(pf("Proforma_ItemsEmpty")).font(AdminType.body).foregroundStyle(AdminSurface.secondaryText).padding(.vertical, 16)
            }
            ForEach(draft.items) { line in
                ProformaLineEditor(line: lineBinding(line), currency: draft.currency, editable: editable) {
                    guard editable else { return }
                    store.draft?.items.removeAll(where: { $0.id == line.id })
                }
                Divider()
            }
            if editable {
                Text(pf("Proforma_CatalogPriceHint")).font(AdminType.caption).foregroundStyle(AdminSurface.secondaryText).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func termsSection(_ draft: ProformaDraft) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionTitle("Proforma_Terms")
            HStack {
                Text(pf("Proforma_Currency")).font(AdminType.subheadline)
                Spacer(); Text(draft.currency).font(AdminType.subheadlineBold).environment(\.layoutDirection, .leftToRight)
            }
            Text(pf("Proforma_CurrencyHint")).font(AdminType.caption).foregroundStyle(AdminSurface.secondaryText)
            Toggle(pf("Proforma_Validity"), isOn: Binding(get: { store.draft?.validUntil != nil }, set: { enabled in
                store.draft?.validUntil = enabled ? ProformaWire.validityString(Date()) : nil
            })).font(AdminType.subheadline).disabled(!editable)
            if let valid = draft.validUntil {
                DatePicker(pf("Proforma_ValidUntil"), selection: Binding(get: { ProformaWire.validityDate(store.draft?.validUntil) ?? Date() }, set: { date in
                    store.draft?.validUntil = ProformaWire.validityString(date)
                }), displayedComponents: .date)
                    .datePickerStyle(.compact).font(AdminType.body).disabled(!editable)
                    .environment(\.timeZone, TimeZone(secondsFromGMT: 0)!)
                if let validity = ProformaWire.validityDate(valid) {
                    Text(validity, style: .date).font(AdminType.caption).foregroundStyle(AdminSurface.secondaryText)
                        .environment(\.timeZone, TimeZone(secondsFromGMT: 0)!)
                }
            }
            ProformaDiscountEditor(title: "Proforma_InvoiceDiscount", discount: Binding(get: { store.draft?.discount ?? ProformaDiscount() }, set: { store.draft?.discount = $0 }), editable: editable)
            VStack(alignment: .leading, spacing: 6) {
                Text(pf("Proforma_Notes")).font(AdminType.subheadlineBold)
                TextField(pf("Proforma_NotesPlaceholder"), text: Binding(get: { store.draft?.notes ?? "" }, set: { store.draft?.notes = String($0.prefix(2000)) }), axis: .vertical)
                    .font(AdminType.body).lineLimit(3...8).padding(12)
                    .background(AdminSurface.backgroundSecondary, in: RoundedRectangle(cornerRadius: 12)).disabled(!editable)
            }
        }
    }

    private func totalsSection(_ draft: ProformaDraft) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle(store.hasUnsavedChanges ? "Proforma_Estimate" : "Proforma_Totals")
            if store.hasUnsavedChanges {
                if let totals = try? draft.estimatedTotals() {
                    totalRows(totals, currency: draft.currency)
                } else {
                    Text(pf("Proforma_Error_InvalidInput")).font(AdminType.footnote).foregroundStyle(AdminSurface.danger)
                }
                Text(pf("Proforma_EstimateHint")).font(AdminType.caption).foregroundStyle(AdminSurface.secondaryText)
            } else if let invoice = store.selected { totalRows(invoice.totals, currency: invoice.currency) }
        }
        .padding(16).background(AdminSurface.backgroundSecondary, in: RoundedRectangle(cornerRadius: 16))
    }

    private func totalRows(_ totals: ProformaTotals, currency: String) -> some View {
        VStack(spacing: 8) {
            amountRow("Proforma_Subtotal", value: totals.subtotalMinor, currency: currency)
            amountRow("Proforma_Discount", value: totals.lineDiscountMinor + totals.discountMinor, currency: currency)
            amountRow("Proforma_Tax", value: totals.taxMinor, currency: currency)
            Divider()
            amountRow("Proforma_Total", value: totals.totalMinor, currency: currency, emphasized: true)
        }
    }

    private func amountRow(_ key: String, value: Int, currency: String, emphasized: Bool = false) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack { Text(pf(key)); Spacer(); Text(money(ProformaDecimal.minor(value), currency: currency)).environment(\.layoutDirection, .leftToRight) }
            VStack(alignment: .leading, spacing: 4) { Text(pf(key)); Text(money(ProformaDecimal.minor(value), currency: currency)).environment(\.layoutDirection, .leftToRight) }
        }.font(emphasized ? AdminType.title3 : AdminType.subheadline)
    }

    private var documentActions: some View {
        VStack(spacing: 8) {
            if store.isMutating { ProgressView(pf("Proforma_Saving")) }
            if store.confirmationPending { Text(pf("Proforma_Confirming")).font(AdminType.caption) }
            if typeSize.isAccessibilitySize { VStack(spacing: 8) { actionButtons } }
            else {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 10) { actionButtons }
                    VStack(spacing: 8) { actionButtons }
                }
            }
        }
        .padding(14).frame(maxWidth: .infinity).background(AdminSurface.surface)
        .overlay(alignment: .top) { Divider() }
    }

    @ViewBuilder private var actionButtons: some View {
        if editable && (store.hasUnsavedChanges || store.selected == nil) {
            Button(pf("Proforma_SaveDraft"), systemImage: "checkmark") { Task { await store.perform("save") } }
                .frame(maxWidth: .infinity, minHeight: 48).buttonStyle(ProformaPrimaryStyle())
        } else if let selected = store.selected {
            if !selected.items.isEmpty && !store.hasUnsavedChanges {
                Button(pf("Proforma_Preview"), systemImage: "doc.text.magnifyingglass") { makePreview(selected) }
                    .frame(maxWidth: .infinity, minHeight: 48).buttonStyle(ProformaSecondaryStyle()).disabled(store.isLocked)
            }
            if canWrite && selected.status == .draft {
                Button(pf("Proforma_Issue"), systemImage: "checkmark.seal") { Task { await store.perform("issue") } }
                    .frame(maxWidth: .infinity, minHeight: 48).buttonStyle(ProformaPrimaryStyle()).disabled(store.isLocked || selected.isExpired)
            } else if canWrite && selected.status == .issued {
                Button(pf("Proforma_Convert"), systemImage: "arrow.right.doc.on.clipboard") { conversionSheet = true }
                    .frame(maxWidth: .infinity, minHeight: 48).buttonStyle(ProformaPrimaryStyle()).disabled(store.isLocked || selected.isExpired)
            }
            if canWrite && selected.status.isEditable && !store.hasUnsavedChanges {
                Menu {
                    Button(pf("Proforma_CancelInvoice"), role: .destructive) { cancellationConfirmation = true }
                } label: { Image(systemName: "ellipsis").frame(minWidth: 44, minHeight: 48) }
                .accessibilityLabel(pf("Proforma_More")).disabled(store.isLocked)
            }
        }
    }

    private var convertedSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(pf("Proforma_Converted_Title"), systemImage: "checkmark.seal.fill").font(AdminType.headline).foregroundStyle(AdminSurface.emerald)
            Text(pf("Proforma_Converted_Detail")).font(AdminType.footnote).foregroundStyle(AdminSurface.secondaryText)
            if let id = store.selected?.convertedTransactionId {
                Button { UIPasteboard.general.string = id } label: {
                    Label(id, systemImage: "doc.on.doc").font(AdminType.subheadline).environment(\.layoutDirection, .leftToRight).frame(minHeight: 44)
                }.accessibilityLabel(pf("Proforma_CopySale"))
            }
            Button(pf("Proforma_ViewSale"), systemImage: "receipt") { fetchActualSale() }.frame(minHeight: 44).disabled(actualReceiptLoading)
            if actualReceiptLoading { ProgressView(pf("Proforma_LoadingSale")) }
        }
    }

    private var pendingPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(pf("Proforma_Confirming"), systemImage: "arrow.triangle.2.circlepath").font(AdminType.subheadlineBold)
            Text(pf("Proforma_ConfirmingHint")).font(AdminType.footnote)
            Button(pf("Proforma_Refresh")) { Task { await store.retryConfirmation() } }.frame(minHeight: 44).disabled(store.isMutating || store.isConfirming)
        }.foregroundStyle(AdminSurface.secondaryText).padding(14).background(AdminSurface.backgroundSecondary, in: RoundedRectangle(cornerRadius: 12))
    }

    private func errorPanel(_ error: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(error, systemImage: "exclamationmark.circle").font(AdminType.footnote).fixedSize(horizontal: false, vertical: true)
            if store.canRetryMutation {
                Text(pf("Proforma_RetrySafeHint")).font(AdminType.caption)
                Button(pf("Proforma_Retry")) { Task { await store.retryMutation() } }.frame(minHeight: 44)
            } else if store.errorIsConflict {
                Button(pf("Proforma_ReloadInvoice")) {
                    if store.hasUnsavedChanges, let selected = store.selected { discardAction = .open(selected) }
                    else { Task { await store.reloadSelection() } }
                }.frame(minHeight: 44)
            } else if !store.hasSelection {
                Button(pf("Proforma_Retry")) { Task { await store.load(branchId: activeBranchID) } }.frame(minHeight: 44)
            }
        }
        .foregroundStyle(AdminSurface.danger).padding(14).frame(maxWidth: .infinity, alignment: .leading)
        .background(AdminSurface.danger.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
    }

    private func status(_ invoice: ProformaInvoice) -> some View {
        Text(invoice.isExpired ? pf("Proforma_Status_expired") : invoice.status.title)
            .font(AdminType.captionBold).padding(.horizontal, 9).padding(.vertical, 5)
            .foregroundStyle(invoice.status == .converted ? AdminSurface.emerald : invoice.isExpired ? AdminSurface.danger : AdminSurface.secondaryText)
            .background(AdminSurface.backgroundSecondary, in: Capsule())
    }

    private func stateMessage(_ title: String, symbol: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: symbol).font(.system(size: 32, weight: .light)).foregroundStyle(AdminSurface.primary).accessibilityHidden(true)
            Text(pf(title)).font(AdminType.title3)
            Text(pf(detail)).font(AdminType.body).foregroundStyle(AdminSurface.secondaryText).fixedSize(horizontal: false, vertical: true)
        }.frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 28)
    }
    private func sectionTitle(_ key: String) -> some View { Text(pf(key)).font(AdminType.headline).accessibilityAddTraits(.isHeader) }
    private func lineBinding(_ original: ProformaLine) -> Binding<ProformaLine> {
        Binding(get: { store.draft?.items.first(where: { $0.id == original.id }) ?? original }, set: { line in
            guard let index = store.draft?.items.firstIndex(where: { $0.id == original.id }) else { return }; store.draft?.items[index] = line
        })
    }
    private func close() { if let onDismiss { onDismiss() } else { dismiss() } }
    private func branchName(_ id: String) -> String {
        branches.branch(for: id)?.localizedName() ?? (activeBranchID == id ? branches.currentBranchDisplayName : id)
    }

    private func fetchActualSale() {
        guard !actualReceiptLoading, let id = store.selected?.convertedTransactionId else { return }
        actualReceiptLoading = true
        PPPOSService.shared().fetchPOSReceipt(forTransactionID: id) { receipt, error in
            Task { @MainActor in
                actualReceiptLoading = false
                if let receipt { actualReceipt = POSCompletedReceipt(receipt: receipt) }
                else { localError = Language.get("Proforma_Error_LoadingSale", alter: nil) }
            }
        }
    }

    private func makePreview(_ invoice: ProformaInvoice) {
        guard !store.hasUnsavedChanges, !store.isLocked else { return }
        do {
            let snapshot = PPProformaPDFSnapshot(
                id: invoice.id, number: invoice.number, revision: invoice.version,
                status: invoice.status.rawValue, statusTitle: invoice.status.title,
                branchName: branchName(invoice.branchId),
                currency: invoice.currency, currencyDigits: 2,
                customerName: invoice.customer?.name ?? pf("Proforma_NoCustomer"),
                customerPhone: invoice.customer?.phone ?? "", customerEmail: invoice.customer?.email ?? "",
                validUntil: ProformaWire.validityDate(invoice.validUntil), issuedAt: invoice.issuedAt ?? invoice.createdAt,
                notes: invoice.notes,
                lines: invoice.items.map { line in
                    PPProformaPDFLine(title: line.name, code: line.sku.isEmpty ? line.barcode : line.sku,
                        unit: line.unitIds.isEmpty ? line.groupName : String(format: pf("Proforma_ExactUnits"), line.unitIds.count),
                        quantity: ProformaDecimal.parse(line.quantity, scale: 3) ?? 0,
                        unitPrice: ProformaDecimal.parse(line.unitPrice, scale: 2) ?? 0,
                        discount: ProformaDecimal.minor(line.lineDiscountMinor + line.globalDiscountMinor),
                        tax: ProformaDecimal.minor(line.taxMinor), total: ProformaDecimal.minor(line.totalMinor))
                }, subtotal: ProformaDecimal.minor(invoice.totals.subtotalMinor),
                discount: ProformaDecimal.minor(invoice.totals.lineDiscountMinor + invoice.totals.discountMinor),
                tax: ProformaDecimal.minor(invoice.totals.taxMinor), total: ProformaDecimal.minor(invoice.totals.totalMinor)
            )
            preview = ProformaPreviewDocument(data: try PPProformaPDFRenderer.render(snapshot: snapshot), number: invoice.number)
        } catch { localError = error.localizedDescription }
    }
}

private enum ProformaDiscardAction { case close, directory, create, open(ProformaInvoice) }
private struct ProformaPreviewDocument: Identifiable { let id = UUID(); let data: Data; let number: String }
private func pf(_ key: String) -> String { Language.get(key, alter: nil) }
private func money(_ value: Decimal, currency: String) -> String {
    let formatter = NumberFormatter(); formatter.locale = Locale(identifier: Language.isRTL() ? "ar" : "en")
    formatter.numberStyle = .currency; formatter.currencyCode = currency
    formatter.minimumFractionDigits = 2; formatter.maximumFractionDigits = 2
    return formatter.string(from: NSDecimalNumber(decimal: value)) ?? ProformaDecimal.string(value) + " " + currency
}

private struct ProformaLineEditor: View {
    @Binding var line: ProformaLine
    let currency: String
    let editable: Bool
    let onRemove: () -> Void
    @Environment(\.dynamicTypeSize) private var typeSize
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 8) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(line.name).font(AdminType.headline).fixedSize(horizontal: false, vertical: true)
                    if !line.groupName.isEmpty { Text(line.groupName).font(AdminType.subheadline).foregroundStyle(AdminSurface.secondaryText) }
                    if !line.sku.isEmpty { Text(line.sku).font(AdminType.caption).environment(\.layoutDirection, .leftToRight).foregroundStyle(AdminSurface.secondaryText) }
                }
                Spacer(minLength: 0)
                if editable {
                    Button(action: onRemove) { Image(systemName: "minus.circle").frame(width: 44, height: 44) }
                        .foregroundStyle(AdminSurface.secondaryText).accessibilityLabel(String(format: pf("Proforma_RemoveItem"), line.name))
                }
            }
            if line.unitIds.isEmpty {
                let layout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 10)) : AnyLayout(HStackLayout(alignment: .top, spacing: 12))
                layout {
                    numericField("Proforma_Quantity", value: $line.quantity, scale: 3)
                    numericField(line.unitsPerGroup > 1 ? "Proforma_GroupPrice" : "Proforma_UnitPrice", value: $line.unitPrice, scale: 2)
                }
            } else {
                Label(String(format: pf("Proforma_ExactUnits"), line.unitIds.count), systemImage: "checkmark.shield").font(AdminType.footnote).foregroundStyle(AdminSurface.secondaryText)
                Text(money(ProformaDecimal.parse(line.unitPrice, scale: 2) ?? 0, currency: currency)).font(AdminType.subheadline).environment(\.layoutDirection, .leftToRight)
            }
            ProformaDiscountEditor(title: "Proforma_LineDiscount", discount: $line.discount, editable: editable)
            numericField("Proforma_TaxRate", value: $line.taxRate, scale: 2)
            Text(pf("Proforma_TaxHint")).font(AdminType.caption).foregroundStyle(AdminSurface.secondaryText)
        }.padding(.vertical, 8)
    }
    private func numericField(_ key: String, value: Binding<String>, scale: Int) -> some View {
        ProformaNumericField(title: key, value: value, scale: scale, editable: editable)
    }
}

private struct ProformaNumericField: View {
    let title: String
    @Binding var value: String
    let scale: Int
    let editable: Bool
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(pf(title)).font(AdminType.captionBold).foregroundStyle(AdminSurface.secondaryText)
            TextField(pf(title), text: $value).keyboardType(.decimalPad)
                .font(AdminType.body).monospacedDigit().environment(\.layoutDirection, .leftToRight)
                .padding(.horizontal, 12).frame(minHeight: 44)
                .background(AdminSurface.backgroundSecondary, in: RoundedRectangle(cornerRadius: 10))
                .disabled(!editable).accessibilityLabel(pf(title))
            if editable && ProformaDecimal.parse(value, scale: scale) == nil {
                Text(pf("Proforma_DecimalHint")).font(AdminType.caption).foregroundStyle(AdminSurface.danger)
            }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct ProformaDiscountEditor: View {
    let title: String
    @Binding var discount: ProformaDiscount
    let editable: Bool
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(pf(title)).font(AdminType.subheadline)
                Spacer()
                Menu {
                    ForEach(["none", "amount", "percent"], id: \.self) { type in
                        Button(pf("Proforma_Discount_" + type)) { discount.type = type; discount.value = "0" }
                    }
                } label: {
                    Label(pf("Proforma_Discount_" + discount.type), systemImage: "chevron.down").font(AdminType.subheadlineBold).frame(minHeight: 44)
                }.disabled(!editable)
            }
            if discount.type != "none" {
                ProformaNumericField(title: discount.type == "percent" ? "Proforma_Percent" : "Proforma_Amount", value: $discount.value, scale: 2, editable: editable)
            }
        }
    }
}

private struct ProformaCatalogSheet: View {
    @ObservedObject var store: ProformaInvoiceStore
    let currency: String
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    Text(pf("Proforma_CatalogHint")).font(AdminType.footnote).foregroundStyle(AdminSurface.secondaryText)
                    if store.catalogLoading && store.catalog.isEmpty { ProgressView(pf("Proforma_CatalogLoading")).frame(maxWidth: .infinity, minHeight: 100) }
                    if let error = store.catalogError {
                        Text(error).foregroundStyle(AdminSurface.danger).font(AdminType.footnote)
                        Button(pf("Proforma_Retry")) { Task { await store.searchCatalog(query) } }.frame(minHeight: 44)
                    } else if !store.catalogLoading && store.catalog.isEmpty {
                        Text(pf("Proforma_CatalogEmpty")).font(AdminType.body).padding(.vertical, 20)
                    }
                    ForEach(store.catalog) { item in
                        Button { store.add(item); dismiss() } label: {
                            VStack(alignment: .leading, spacing: 6) {
                                Text(item.name).font(AdminType.headline).foregroundStyle(AdminSurface.primaryText)
                                if !item.groupName.isEmpty { Text(item.groupName).font(AdminType.subheadline).foregroundStyle(AdminSurface.secondaryText) }
                                HStack {
                                    Text(money(ProformaDecimal.parse(item.unitPrice, scale: 2) ?? 0, currency: item.currency)).environment(\.layoutDirection, .leftToRight)
                                    Spacer(); Image(systemName: "plus.circle.fill").foregroundStyle(AdminSurface.primary)
                                }.font(AdminType.subheadlineBold)
                                Text(String(format: pf("Proforma_Available"), item.availableQuantity)).font(AdminType.caption).foregroundStyle(AdminSurface.secondaryText)
                            }.frame(maxWidth: .infinity, minHeight: 44, alignment: .leading).padding(14)
                                .background(AdminSurface.backgroundSecondary, in: RoundedRectangle(cornerRadius: 12))
                        }.buttonStyle(ProformaPressStyle()).disabled(item.currency != currency || store.isLocked)
                    }
                    if store.catalogCursor != nil {
                        Button(pf("Proforma_LoadMore")) { Task { await store.searchCatalog(query, append: true) } }
                            .frame(maxWidth: .infinity, minHeight: 44).disabled(store.catalogLoading)
                    }
                }.padding(20)
            }
            .navigationTitle(pf("Proforma_AddItem"))
            .searchable(text: $query, prompt: pf("Proforma_CatalogSearch"))
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button(pf("Proforma_Close")) { dismiss() } } }
            .task(id: query) {
                do { try await Task.sleep(for: .milliseconds(query.isEmpty ? 0 : 250)) } catch { return }
                guard !Task.isCancelled else { return }; await store.searchCatalog(query)
            }
        }.environment(\.layoutDirection, Language.isRTL() ? .rightToLeft : .leftToRight)
    }
}

private struct ProformaConversionSheet: View {
    let invoice: ProformaInvoice
    @ObservedObject var store: ProformaInvoiceStore
    @Environment(\.dismiss) private var dismiss
    @State private var method = "cash"
    @State private var cashReceived = ""
    @State private var confirm = false
    private var validCash: Bool {
        method == "card" || (ProformaDecimal.parse(cashReceived, scale: 2).map { $0 >= ProformaDecimal.minor(invoice.totals.totalMinor) } ?? false)
    }
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text(invoice.number).font(AdminType.title2).environment(\.layoutDirection, .leftToRight)
                    Text(money(ProformaDecimal.minor(invoice.totals.totalMinor), currency: invoice.currency)).font(AdminType.title).environment(\.layoutDirection, .leftToRight)
                    Text(pf("Proforma_ConvertWarning")).font(AdminType.body).fixedSize(horizontal: false, vertical: true)
                    Picker(pf("Proforma_Payment"), selection: $method) {
                        Text(pf("Proforma_Cash")).tag("cash"); Text(pf("Proforma_Card")).tag("card")
                    }.pickerStyle(.menu).font(AdminType.body).disabled(store.isLocked)
                    if method == "cash" {
                        ProformaNumericField(title: "Proforma_CashReceived", value: $cashReceived, scale: 2, editable: !store.isLocked)
                        if let cash = ProformaDecimal.parse(cashReceived, scale: 2), cash >= ProformaDecimal.minor(invoice.totals.totalMinor) {
                            Text(String(format: pf("Proforma_Change"), money(cash - ProformaDecimal.minor(invoice.totals.totalMinor), currency: invoice.currency)))
                                .font(AdminType.subheadline).environment(\.layoutDirection, .leftToRight)
                        }
                    } else { Text(pf("Proforma_CardRecordedHint")).font(AdminType.footnote).foregroundStyle(AdminSurface.secondaryText) }
                    if store.isMutating { ProgressView(pf("Proforma_Converting")) }
                    if store.confirmationPending {
                        Text(pf("Proforma_ConfirmingHint")).font(AdminType.footnote)
                        Button(pf("Proforma_Refresh")) { Task { await store.retryConfirmation() } }.frame(minHeight: 44).disabled(store.isConfirming)
                    }
                    if let error = store.error {
                        Text(error).font(AdminType.footnote).foregroundStyle(AdminSurface.danger)
                        if store.canRetryMutation {
                            Text(pf("Proforma_RetrySafeHint")).font(AdminType.caption)
                            Button(pf("Proforma_Retry")) { Task { await store.retryMutation() } }.frame(minHeight: 44)
                        }
                    }
                    Button(pf("Proforma_ConfirmSale"), systemImage: "checkmark.seal") { confirm = true }
                        .frame(maxWidth: .infinity, minHeight: 48).buttonStyle(ProformaPrimaryStyle())
                        .disabled(store.isLocked || !validCash || store.selected?.status != .issued)
                }.padding(24).frame(maxWidth: 620, alignment: .leading).frame(maxWidth: .infinity)
            }
            .navigationTitle(pf("Proforma_Convert"))
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button(pf("Proforma_Close")) { dismiss() }.disabled(store.isLocked) } }
            .confirmationDialog(pf("Proforma_ConfirmSale"), isPresented: $confirm, titleVisibility: .visible) {
                Button(pf("Proforma_ConfirmSale")) { Task { await store.perform("convert", paymentMethod: method, cashReceived: cashReceived) } }
                Button(pf("Proforma_KeepInvoice"), role: .cancel) {}
            } message: { Text(pf("Proforma_ConvertWarning")) }
            .onAppear { cashReceived = ProformaDecimal.string(ProformaDecimal.minor(invoice.totals.totalMinor)) }
            .onChange(of: store.selected?.status) { _, status in if status == .converted && !store.confirmationPending { dismiss() } }
        }.interactiveDismissDisabled(store.isLocked)
    }
}

private struct ProformaPressStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.opacity(configuration.isPressed ? 0.72 : 1)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: configuration.isPressed)
    }
}
private struct ProformaPrimaryStyle: ButtonStyle {
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(AdminType.headline).padding(.horizontal, 14)
            .foregroundStyle(Color.white).background(enabled ? (configuration.isPressed ? AdminSurface.primaryPressed : AdminSurface.primary) : AdminSurface.secondaryText, in: RoundedRectangle(cornerRadius: 12))
    }
}
private struct ProformaSecondaryStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(AdminType.subheadlineBold).padding(.horizontal, 12)
            .foregroundStyle(AdminSurface.primaryText).background(configuration.isPressed ? AdminSurface.hairline : AdminSurface.backgroundSecondary, in: RoundedRectangle(cornerRadius: 12))
    }
}

/// A scoped guard on the existing UIKit owner; it creates no navigation/session root.
private struct ProformaNavigationGuard: UIViewControllerRepresentable {
    let blocked: Bool
    func makeUIViewController(context: Context) -> GuardController { GuardController() }
    func updateUIViewController(_ controller: GuardController, context: Context) { controller.setBlocked(blocked) }
    static func dismantleUIViewController(_ controller: GuardController, coordinator: ()) { controller.restore() }

    final class GuardController: UIViewController {
        private var blocked = false
        private weak var host: UIViewController?
        private weak var navigation: UINavigationController?
        private var priorPopEnabled: Bool?
        private var priorModalBlocked: Bool?

        override func loadView() { let view = UIView(); view.isUserInteractionEnabled = false; self.view = view }
        override func didMove(toParent parent: UIViewController?) { super.didMove(toParent: parent); apply() }
        override func viewDidAppear(_ animated: Bool) { super.viewDidAppear(animated); apply() }
        override func viewWillDisappear(_ animated: Bool) { super.viewWillDisappear(animated); restore() }
        func setBlocked(_ value: Bool) { blocked = value; apply() }

        private func apply() {
            guard let parent else { return }
            if !blocked { restore(); return }
            if host == nil {
                host = parent; priorModalBlocked = parent.isModalInPresentation
                navigation = parent.navigationController
                priorPopEnabled = navigation?.interactivePopGestureRecognizer?.isEnabled
            }
            host?.isModalInPresentation = true
            navigation?.interactivePopGestureRecognizer?.isEnabled = false
        }

        func restore() {
            if let priorModalBlocked { host?.isModalInPresentation = priorModalBlocked }
            if let priorPopEnabled { navigation?.interactivePopGestureRecognizer?.isEnabled = priorPopEnabled }
            host = nil; navigation = nil; priorModalBlocked = nil; priorPopEnabled = nil
        }
    }
}
