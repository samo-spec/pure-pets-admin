//
//  PPBranchSelectionGateView.swift
//  PurePetsAdmin
//

import SwiftUI

/// A single, branch-scoped decision surface. The branch manager remains the
/// authority for eligible branches and for changing the working context.
public struct PPBranchSelectionGateView: View {
    @ObservedObject private var contextStore = BranchContextStore.shared
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    @State private var searchText = ""
    @State private var selectionError: String?
    @State private var selectionInProgress = false

    public var customTitle: String? = nil
    public var customSubtitle: String? = nil
    public var selectedBranchID: String? = nil
    public var allowGlobalAccess: Bool = true
    public var onSelectBranch: ((PPBranchModel) -> Void)? = nil

    public init(
        title: String? = nil,
        subtitle: String? = nil,
        selectedBranchID: String? = nil,
        allowGlobalAccess: Bool = true,
        onSelectBranch: ((PPBranchModel) -> Void)? = nil
    ) {
        self.customTitle = title
        self.customSubtitle = subtitle
        self.selectedBranchID = selectedBranchID
        self.allowGlobalAccess = allowGlobalAccess
        self.onSelectBranch = onSelectBranch
    }

    private var chosenBranchID: String? {
        if let selectedBranchID, !selectedBranchID.isEmpty { return selectedBranchID }
        return contextStore.activeBranch?.branchID
    }

    private var sheetDetents: Set<PresentationDetent> {
        guard !dynamicTypeSize.isAccessibilitySize, contextStore.availableBranches.count < 5 else {
            return [.large]
        }
        let branchCount = max(1, contextStore.availableBranches.count)
        let height = CGFloat(300 + branchCount * 104 + (branchCount == 1 ? 34 : 0))
        return [.height(height), .large]
    }

    private var visibleBranches: [PPBranchModel] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let matches = query.isEmpty ? contextStore.availableBranches : contextStore.availableBranches.filter {
            $0.localizedName().localizedCaseInsensitiveContains(query) ||
            $0.code.localizedCaseInsensitiveContains(query) ||
            $0.address.localizedCaseInsensitiveContains(query) ||
            $0.phone.localizedCaseInsensitiveContains(query)
        }
        guard let chosenBranchID else { return matches }
        // Keep the branch in use at the top without duplicating it in a hero.
        return matches.filter { $0.branchID == chosenBranchID } +
            matches.filter { $0.branchID != chosenBranchID }
    }

    public var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    heading

                    if contextStore.availableBranches.count > 3 || !searchText.isEmpty {
                        searchField
                    }

                    branchChoices

                    if let selectionError {
                        Label(selectionError, systemImage: "exclamationmark.circle.fill")
                            .font(.custom("Beiruti-Medium", size: 15, relativeTo: .body))
                            .foregroundStyle(Color(uiColor: .systemRed))
                            .accessibilityAddTraits(.updatesFrequently)
                    }
                }
                .frame(maxWidth: 560, alignment: .leading)
                .padding(.horizontal, 22)
                .padding(.top, 20)
                .padding(.bottom, 40)
                .frame(maxWidth: .infinity)
            }
            .background(Color(uiColor: .systemGroupedBackground).ignoresSafeArea())
            .navigationBarHidden(true)
            .interactiveDismissDisabled(contextStore.needsBranchSelection)
        }
        .navigationViewStyle(.stack)
        .presentationDetents(sheetDetents)
        .presentationDragIndicator(.visible)
        .environment(\.layoutDirection, Language.isRTL() ? .rightToLeft : .leftToRight)
        .onAppear { contextStore.reload() }
        .onChange(of: contextStore.availableBranches.count) { _ in selectionError = nil }
    }

    private var heading: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center) {
                if !contextStore.needsBranchSelection {
                    Button {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Color(uiColor: .secondaryLabel))
                            .frame(width: 44, height: 44)
                            .background(Color(uiColor: .secondarySystemGroupedBackground), in: Circle())
                    }
                    .accessibilityLabel(Language.get("BranchContext_Close", alter: nil))
                }

                Spacer()

                Image(systemName: "building.2.fill")
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(AdminSurface.primary)
                    .frame(width: 44, height: 44)
                    .background(AdminSurface.primary.opacity(0.10), in: RoundedRectangle(cornerRadius: 14))
                    .accessibilityHidden(true)
            }

            VStack(alignment: .leading, spacing: 5) {
                Text(customTitle ?? Language.get("BranchContext_Gate_Title", alter: nil))
                    .font(.custom("Beiruti-Bold", size: 28, relativeTo: .title))
                    .foregroundStyle(Color(uiColor: .label))
                    .fixedSize(horizontal: false, vertical: true)

                Text(customSubtitle ?? Language.get("BranchContext_Gate_Subtitle", alter: nil))
                    .font(.custom("Beiruti-Regular", size: 16, relativeTo: .body))
                    .foregroundStyle(Color(uiColor: .secondaryLabel))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .multilineTextAlignment(.leading)
        }
    }

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(Color(uiColor: .secondaryLabel))

            TextField(Language.get("BranchContext_Search_Placeholder", alter: nil), text: $searchText)
                .font(.custom("Beiruti-Medium", size: 16, relativeTo: .body))
                .textInputAutocapitalization(.never)
                .disableAutocorrection(true)
                .accessibilityLabel(Language.get("BranchContext_Search_Placeholder", alter: nil))

            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(Color(uiColor: .secondaryLabel))
                        .frame(width: 44, height: 44)
                }
                .accessibilityLabel(Language.get("BranchContext_Search_Clear", alter: nil))
            }
        }
        .padding(.leading, 16)
        .padding(.trailing, 4)
        .frame(minHeight: 54)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(Color(uiColor: .separator).opacity(0.45)))
    }

    private var branchChoices: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack(alignment: .firstTextBaseline) {
                Text(Language.get("BranchContext_Available_Section", alter: nil))
                    .font(.custom("Beiruti-Bold", size: 18, relativeTo: .headline))
                    .foregroundStyle(Color(uiColor: .label))

                Spacer()

                Text("\(visibleBranches.count)")
                    .font(.system(.subheadline, design: .rounded, weight: .semibold))
                    .foregroundStyle(Color(uiColor: .secondaryLabel))
                    .accessibilityLabel(Language.get("BranchContext_Available_Section", alter: nil))
                    .accessibilityValue("\(visibleBranches.count)")
            }

            if visibleBranches.isEmpty {
                emptyBranches
            } else {
                LazyVStack(spacing: 10) {
                    ForEach(visibleBranches, id: \.branchID) { branch in
                        branchRow(branch)
                    }
                }

                if contextStore.availableBranches.count == 1 && searchText.isEmpty {
                    Text(Language.get("BranchContext_SingleBranch_Hint", alter: nil))
                        .font(.custom("Beiruti-Regular", size: 14, relativeTo: .footnote))
                        .foregroundStyle(Color(uiColor: .secondaryLabel))
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 2)
                }
            }
        }
    }

    private var emptyBranches: some View {
        VStack(alignment: .leading, spacing: 12) {
            Image(systemName: searchText.isEmpty ? "building.2.slash" : "magnifyingglass")
                .font(.system(size: 22, weight: .medium))
                .foregroundStyle(AdminSurface.primary)

            Text(Language.get(searchText.isEmpty ? "BranchContext_NoBranches_Hint" : "BranchContext_No_Results", alter: nil))
                .font(.custom("Beiruti-Medium", size: 16, relativeTo: .body))
                .foregroundStyle(Color(uiColor: .secondaryLabel))
                .fixedSize(horizontal: false, vertical: true)

            if searchText.isEmpty {
                Button(Language.get("BranchContext_Refresh", alter: nil)) { contextStore.reload() }
                    .font(.custom("Beiruti-Bold", size: 15, relativeTo: .body))
                    .foregroundStyle(AdminSurface.primary)
                    .frame(minHeight: 44)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20))
    }

    private func branchRow(_ branch: PPBranchModel) -> some View {
        let selected = branch.branchID == chosenBranchID
        let isDefault = branch.isDefault || branch.branchID == contextStore.currentStaff?.defaultBranchID

        return Button {
            select(branch)
        } label: {
            HStack(alignment: .center, spacing: 13) {
                Image(systemName: "building.2")
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(selected ? Color.white : AdminSurface.primary)
                    .frame(width: 46, height: 46)
                    .background(selected ? AdminSurface.primary : AdminSurface.primary.opacity(0.10),
                                in: RoundedRectangle(cornerRadius: 15))
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 3) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(branch.localizedName())
                            .font(.custom("Beiruti-Bold", size: 19, relativeTo: .headline))
                            .foregroundStyle(Color(uiColor: .label))
                            .fixedSize(horizontal: false, vertical: true)

                        if isDefault {
                            Image(systemName: "star.fill")
                                .font(.system(size: 11))
                                .foregroundStyle(Color(uiColor: .systemOrange))
                                .accessibilityLabel(Language.get("BranchContext_DefaultBadge", alter: nil))
                        }
                    }

                    if !branch.address.isEmpty {
                        Text(branch.address)
                            .font(.custom("Beiruti-Regular", size: 14, relativeTo: .subheadline))
                            .foregroundStyle(Color(uiColor: .secondaryLabel))
                            .lineLimit(2)
                    }

                    HStack(spacing: 8) {
                        if !branch.code.isEmpty {
                            Text(branch.code)
                                .font(.system(.caption2, design: .monospaced, weight: .medium))
                                .environment(\.layoutDirection, .leftToRight)
                        }
                        Text(branch.localizedStockModeName())
                            .font(.custom("Beiruti-Medium", size: 12, relativeTo: .caption))
                    }
                    .foregroundStyle(Color(uiColor: .secondaryLabel))
                }

                Spacer(minLength: 0)

                Image(systemName: selected ? "checkmark.circle.fill" : "chevron.forward")
                    .font(.system(size: selected ? 20 : 14, weight: .semibold))
                    .foregroundStyle(selected ? AdminSurface.primary : Color(uiColor: .tertiaryLabel))
                    .accessibilityHidden(true)
            }
            .padding(15)
            .frame(maxWidth: .infinity, minHeight: 86, alignment: .leading)
            .background(selected ? AdminSurface.primary.opacity(0.075) : Color(uiColor: .secondarySystemGroupedBackground),
                        in: RoundedRectangle(cornerRadius: 22))
            .overlay(RoundedRectangle(cornerRadius: 22)
                .stroke(selected ? AdminSurface.primary.opacity(0.48) : Color(uiColor: .separator).opacity(0.4),
                        lineWidth: selected ? 1.5 : 0.7))
            .contentShape(RoundedRectangle(cornerRadius: 22))
        }
        .buttonStyle(PPBranchGatePressStyle())
        .disabled(selectionInProgress)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(branch.localizedName())
        .accessibilityValue(selected ? Language.get(onSelectBranch == nil ? "BranchContext_Current_Active" : "BranchContext_Selected_Field", alter: nil) : branch.localizedStockModeName())
        .accessibilityHint(Language.get("BranchContext_Select_Hint", alter: nil))
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }

    private func select(_ branch: PPBranchModel) {
        guard !selectionInProgress else { return }
        guard contextStore.availableBranches.contains(where: { $0.branchID == branch.branchID }) else {
            selectionError = Language.get("BranchContext_Selection_Failed", alter: nil)
            UINotificationFeedbackGenerator().notificationOccurred(.error)
            return
        }

        selectionInProgress = true
        selectionError = nil
        if let onSelectBranch {
            onSelectBranch(branch)
        } else if !contextStore.selectBranch(branch) {
            selectionInProgress = false
            selectionError = Language.get("BranchContext_Selection_Failed", alter: nil)
            UINotificationFeedbackGenerator().notificationOccurred(.error)
            return
        }

        UISelectionFeedbackGenerator().selectionChanged()
        if reduceMotion {
            dismiss()
        } else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.16) { dismiss() }
        }
    }
}

private struct PPBranchGatePressStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.985 : 1)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

// Used by other established Admin views as well as this branch surface.
extension Color {
    static let emerald600 = Color(red: 5/255, green: 150/255, blue: 105/255)
    static let amber600 = Color(red: 217/255, green: 119/255, blue: 6/255)
}
