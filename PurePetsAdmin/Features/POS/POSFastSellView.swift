//
//  POSFastSellView.swift
//  PurePetsAdmin
//
//  Quick sale screen: item search, cart builder, total display,
//  payment method picker (cash/card), submit button.
//

import SwiftUI

// MARK: - POS Cart Item

struct POSCartItem: Identifiable, Equatable {
    let id = UUID()
    let accessory: PetAccessory
    var quantity: Int = 1

    var lineTotal: Double { accessory.price.doubleValue * Double(quantity) }

    static func == (lhs: POSCartItem, rhs: POSCartItem) -> Bool {
        lhs.id == rhs.id && lhs.quantity == rhs.quantity
    }
}

// MARK: - POS FastSell ViewModel

@MainActor
final class POSFastSellViewModel: ObservableObject {
    @Published var searchText: String = ""
    @Published private(set) var allAccessories: [PetAccessory] = []
    @Published var cartItems: [POSCartItem] = []
    @Published var selectedPaymentMethod: String = "cash"
    @Published private(set) var isSubmitting = false
    @Published var submitError: String?
    @Published var submitSuccess = false

    private var listener: AnyObject?

    var searchResults: [PetAccessory] {
        guard !searchText.isEmpty else { return allAccessories }
        let q = searchText.lowercased()
        return allAccessories.filter {
            $0.name.lowercased().contains(q)
        }
    }

    var cartTotal: Double {
        cartItems.reduce(0) { $0 + $1.lineTotal }
    }

    var cartItemCount: Int {
        cartItems.reduce(0) { $0 + $1.quantity }
    }

    let paymentMethods: [(key: String, title: String, icon: String)] = [
        ("cash", "POS_Cash", "banknote.fill"),
        ("card", "POS_Card", "creditcard.fill")
    ]

    func startListening() {
        listener = AccessoryManager.shared().observeAllAccessories { [weak self] items, error in
            Task { @MainActor in
                guard let self else { return }
                if error == nil {
                    self.allAccessories = items ?? []
                }
            }
        }
    }

    func stopListening() {
        if let reg = listener as? NSObjectProtocol {
            NotificationCenter.default.removeObserver(reg)
        }
        listener = nil
    }

    func addToCart(_ accessory: PetAccessory) {
        if let idx = cartItems.firstIndex(where: { $0.accessory.accessoryID == accessory.accessoryID }) {
            cartItems[idx].quantity += 1
        } else {
            cartItems.append(POSCartItem(accessory: accessory, quantity: 1))
        }
    }

    func removeFromCart(_ item: POSCartItem) {
        cartItems.removeAll { $0.id == item.id }
    }

    func increaseQuantity(_ item: POSCartItem) {
        guard let idx = cartItems.firstIndex(where: { $0.id == item.id }) else { return }
        cartItems[idx].quantity += 1
    }

    func decreaseQuantity(_ item: POSCartItem) {
        guard let idx = cartItems.firstIndex(where: { $0.id == item.id }) else { return }
        if cartItems[idx].quantity > 1 {
            cartItems[idx].quantity -= 1
        } else {
            cartItems.remove(at: idx)
        }
    }

    func submitOrder() {
        guard !cartItems.isEmpty else { return }
        isSubmitting = true
        submitError = nil

        let items: [[String: Any]] = cartItems.map { item in
            [
                "itemID": item.accessory.accessoryID,
                "name": item.accessory.name,
                "price": item.accessory.price.doubleValue,
                "quantity": item.quantity
            ]
        }

        PPPOSService.shared().submitPOSOrder(
            withItems: items,
            total: cartTotal,
            paymentMethod: selectedPaymentMethod
        ) { [weak self] orderID, error in
            Task { @MainActor in
                guard let self else { return }
                self.isSubmitting = false
                if let error {
                    self.submitError = error.localizedDescription
                    return
                }
                self.submitSuccess = true
                self.cartItems = []
                self.searchText = ""
            }
        }
    }
}

// MARK: - POS FastSell View

struct AdminPOSFastSellView: View {
    let session: AdminSession
    var onDismiss: (() -> Void)? = nil
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel = POSFastSellViewModel()
    @State private var showsItemPicker = false

    init(session: AdminSession, onDismiss: (() -> Void)? = nil) {
        self.session = session
        self.onDismiss = onDismiss
    }

    var body: some View {
        ZStack {
            AdminSurface.background.ignoresSafeArea()

            VStack(spacing: 0) {
                dossierHeaderView
                cartSummaryHeader
                Divider().background(AdminSurface.hairline)
                cartItemsList
                Divider().background(AdminSurface.hairline)
                paymentAndSubmit
            }

            if viewModel.isSubmitting {
                AdminLoadingOverlay(message: Language.get("POS_Submitting", alter: "جارٍ التقديم..."))
            }
        }
        .environment(\.layoutDirection, Language.isRTL() ? .rightToLeft : .leftToRight)
        .sheet(isPresented: $showsItemPicker) {
            itemPickerSheet
        }
        .onAppear { viewModel.startListening() }
        .onDisappear { viewModel.stopListening() }
        .alert(
            Language.get("POS_Order_Submitted", alter: "تم تقديم الطلب"),
            isPresented: $viewModel.submitSuccess
        ) {
            Button(Language.get("OK", alter: "موافق")) {}
        } message: {
            Text(Language.get("POS_Order_Success_Message", alter: "تم تقديم الطلب بنجاح"))
        }
        .alert(
            Language.get("Error", alter: "خطأ"),
            isPresented: Binding(
                get: { viewModel.submitError != nil },
                set: { if !$0 { viewModel.submitError = nil } }
            )
        ) {
            Button(Language.get("OK", alter: "موافق")) {}
        } message: {
            Text(viewModel.submitError ?? "")
        }
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

                Button {
                    showsItemPicker = true
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "plus")
                            .font(.system(size: 14, weight: .bold))
                        Text(Language.get("Add", alter: "إضافة منتج"))
                            .font(AdminType.captionBold)
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 14)
                    .frame(minHeight: 36)
                    .background(AdminSurface.primary, in: Capsule())
                }
                .accessibilityLabel(Language.get("Add", alter: "إضافة منتج"))
            }

            Text(Language.get("CommandCenter_Work_Workspace", alter: "مساحة العمليات") + " / " + Language.get("POS_Title", alter: "البيع السريع"))
                .font(AdminType.caption1)
                .foregroundColor(AdminSurface.secondaryText)
                .padding(.top, 2)

            Text(Language.get("POS_Title", alter: "نقطة البيع السريع"))
                .font(AdminType.title2)
                .foregroundColor(AdminSurface.primaryText)
        }
        .padding(.horizontal, AdminSpacing.screenMargin)
        .padding(.top, AdminSpacing.xs)
    }

    private var cartSummaryHeader: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(Language.get("POS_Cart", alter: "\u{0633}\u{0644}\u{0629} \u{0627}\u{0644}\u{0645}\u{0634}\u{062a}\u{0631}\u{064a}\u{0627}\u{062a}"))
                    .font(AdminType.captionBold)
                    .foregroundColor(AdminSurface.secondaryText)
                HStack(spacing: 4) {
                    Text("\(viewModel.cartItemCount)")
                        .font(AdminType.title2)
                        .foregroundColor(AdminSurface.primaryText)
                    Text(Language.get("POS_Items", alter: "\u{0639}\u{0646}\u{0627}\u{0635}\u{0631}"))
                        .font(AdminType.subheadline)
                        .foregroundColor(AdminSurface.secondaryText)
                }
            }
            Spacer()
            Text(formatCurrency(viewModel.cartTotal))
                .font(AdminType.title2)
                .foregroundColor(AdminSurface.primaryText)
        }
        .padding(.horizontal, AdminSpacing.screenMargin)
        .padding(.vertical, AdminSpacing.md)
    }

    @ViewBuilder
    private var cartItemsList: some View {
        if viewModel.cartItems.isEmpty {
            VStack(spacing: AdminSpacing.lg) {
                Spacer()
                Image(systemName: "cart.fill")
                    .font(.system(size: 40, weight: .light))
                    .foregroundColor(AdminSurface.secondaryText.opacity(0.4))
                Text(Language.get("POS_Empty_Cart", alter: "\u{0627}\u{0644}\u{0633}\u{0644}\u{0629} \u{0641}\u{0627}\u{0631}\u{063a}\u{0629}"))
                    .font(AdminType.headline)
                    .foregroundColor(AdminSurface.secondaryText)
                Text(Language.get("POS_Tap_Add", alter: "\u{0627}\u{0636}\u{063a}\u{0637} + \u{0644}\u{0625}\u{0636}\u{0627}\u{0641}\u{0629} \u{0645}\u{0646}\u{062a}\u{062c}\u{0627}\u{062a}"))
                    .font(AdminType.subheadline)
                    .foregroundColor(AdminSurface.secondaryText.opacity(0.6))
                Spacer()
            }
            .frame(maxWidth: .infinity)
        } else {
            ScrollView {
                LazyVStack(spacing: AdminSpacing.sm) {
                    ForEach(viewModel.cartItems) { item in
                        CartItemRow(
                            item: item,
                            onIncrease: { viewModel.increaseQuantity(item) },
                            onDecrease: { viewModel.decreaseQuantity(item) },
                            onRemove: { viewModel.removeFromCart(item) }
                        )
                    }
                }
                .padding(.horizontal, AdminSpacing.screenMargin)
                .padding(.vertical, AdminSpacing.sm)
            }
        }
    }

    private var paymentAndSubmit: some View {
        VStack(spacing: AdminSpacing.sm) {
            HStack(spacing: AdminSpacing.sm) {
                ForEach(viewModel.paymentMethods, id: \.key) { method in
                    Button {
                        viewModel.selectedPaymentMethod = method.key
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: method.icon)
                                .font(.system(size: 14, weight: .medium))
                            Text(Language.get(method.title, alter: method.key))
                                .font(AdminType.captionBold)
                        }
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: AdminTouchTarget.comfortable)
                        .background(
                            viewModel.selectedPaymentMethod == method.key
                                ? AdminSurface.primary
                                : AdminSurface.control,
                            in: RoundedRectangle(cornerRadius: AdminRadius.medium)
                        )
                        .foregroundColor(
                            viewModel.selectedPaymentMethod == method.key
                                ? .white
                                : AdminSurface.secondaryText
                        )
                    }
                }
            }

            Button {
                viewModel.submitOrder()
            } label: {
                HStack {
                    Text(Language.get("POS_Submit", alter: "\u{062a}\u{0642}\u{062f}\u{064a}\u{0645} \u{0627}\u{0644}\u{0637}\u{0644}\u{0628}"))
                        .font(AdminType.headline)
                    Spacer()
                    Text(formatCurrency(viewModel.cartTotal))
                        .font(AdminType.headline)
                }
                .padding(.horizontal, AdminSpacing.base)
                .frame(minHeight: AdminTouchTarget.comfortable)
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(AdminSurface.primary)
            .disabled(viewModel.cartItems.isEmpty || viewModel.isSubmitting)
        }
        .padding(.horizontal, AdminSpacing.screenMargin)
        .padding(.vertical, AdminSpacing.md)
        .background(.ultraThinMaterial)
    }

    private var itemPickerSheet: some View {
        NavigationView {
            VStack(spacing: 0) {
                AdminSearchField(
                    text: $viewModel.searchText,
                    placeholder: Language.get("POS_Search_Items", alter: "\u{0627}\u{0628}\u{062d}\u{062b} \u{0639}\u{0646} \u{0645}\u{0646}\u{062a}\u{062c}...")
                )
                .padding()

                ScrollView {
                    LazyVStack(spacing: AdminSpacing.sm) {
                        ForEach(viewModel.searchResults, id: \.accessoryID) { accessory in
                            Button {
                                viewModel.addToCart(accessory)
                                showsItemPicker = false
                            } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(accessory.name)
                                            .font(AdminType.calloutBold)
                                            .foregroundColor(AdminSurface.primaryText)
                                        Text(stockLabel(for: accessory))
                                            .font(AdminType.caption2)
                                            .foregroundColor(
                                                accessory.quantity > 0 ? AdminSurface.secondaryText : .red
                                            )
                                    }
                                    Spacer()
                                    Text(formatCurrency(accessory.price.doubleValue))
                                        .font(AdminType.calloutBold)
                                        .foregroundColor(AdminSurface.primaryText)
                                }
                                .padding(.horizontal, AdminSpacing.base)
                                .frame(minHeight: AdminTouchTarget.minimum)
                            }
                            .disabled(accessory.quantity <= 0 || accessory.noStock)

                            if accessory.accessoryID != viewModel.searchResults.last?.accessoryID {
                                Divider().background(AdminSurface.hairline)
                                    .padding(.leading, AdminSpacing.base)
                            }
                        }
                    }
                    .padding(.horizontal, AdminSpacing.screenMargin)
                }
            }
            .background(AdminSurface.background)
            .navigationTitle(Language.get("POS_Add_Item", alter: "\u{0625}\u{0636}\u{0627}\u{0641}\u{0629} \u{0645}\u{0646}\u{062a}\u{062c}"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(Language.get("Cancel", alter: "\u{0625}\u{0644}\u{063a}\u{0627}\u{0621}")) {
                        showsItemPicker = false
                    }
                }
            }
        }
    }

    private func formatCurrency(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "SAR"
        return formatter.string(from: NSNumber(value: value)) ?? "\(value)"
    }

    private func stockLabel(for accessory: PetAccessory) -> String {
        let stockTitle = Language.get("Stock", alter: "\u{0627}\u{0644}\u{0645}\u{062e}\u{0632}\u{0648}\u{0646}")
        return "\(stockTitle): \(accessory.quantity)"
    }
}

// MARK: - Cart Item Row

private struct CartItemRow: View {
    let item: POSCartItem
    let onIncrease: () -> Void
    let onDecrease: () -> Void
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: AdminSpacing.md) {
            VStack(alignment: .leading, spacing: 2) {
                Text(item.accessory.name)
                    .font(AdminType.calloutBold)
                    .foregroundColor(AdminSurface.primaryText)
                Text(formatCurrency(item.accessory.price.doubleValue))
                    .font(AdminType.caption2)
                    .foregroundColor(AdminSurface.secondaryText)
            }

            Spacer()

            HStack(spacing: 2) {
                Button(action: onDecrease) {
                    Image(systemName: "minus")
                        .font(.system(size: 12, weight: .bold))
                        .frame(width: 28, height: 28)
                }
                .foregroundColor(AdminSurface.primary)
                .background(AdminSurface.control, in: Circle())

                Text("\(item.quantity)")
                    .font(AdminType.calloutBold)
                    .foregroundColor(AdminSurface.primaryText)
                    .frame(minWidth: 28)

                Button(action: onIncrease) {
                    Image(systemName: "plus")
                        .font(.system(size: 12, weight: .bold))
                        .frame(width: 28, height: 28)
                }
                .foregroundColor(.white)
                .background(AdminSurface.primary, in: Circle())
            }

            Text(formatCurrency(item.lineTotal))
                .font(AdminType.calloutBold)
                .foregroundColor(AdminSurface.primaryText)
                .frame(minWidth: 70, alignment: .trailing)

            Button(action: onRemove) {
                Image(systemName: "trash.fill")
                    .font(.system(size: 14))
                    .foregroundColor(.red)
                    .frame(width: AdminTouchTarget.minimum, height: AdminTouchTarget.minimum)
            }
        }
        .padding(AdminSpacing.md)
        .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: AdminRadius.medium))
        .overlay(RoundedRectangle(cornerRadius: AdminRadius.medium).stroke(AdminSurface.hairline))
    }

    private func formatCurrency(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "SAR"
        return formatter.string(from: NSNumber(value: value)) ?? "\(value)"
    }
}
