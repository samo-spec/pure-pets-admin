#!/usr/bin/env python3
from pathlib import Path


def replace_once(path: str, old: str, new: str) -> None:
    p = Path(path)
    text = p.read_text()
    if new in text:
        return
    if old not in text:
        raise RuntimeError(f"Expected source block not found in {path}: {old[:120]!r}")
    p.write_text(text.replace(old, new, 1))


# -----------------------------------------------------------------------------
# Global shell: nested Command workflows are focused task surfaces. Keep the
# five-tab dock on roots, but remove it once Command pushes into a detail/editor.
# -----------------------------------------------------------------------------
shell = "PurePetsAdmin/App/AdminAppShell.swift"
replace_once(
    shell,
    "    @State private var selectedTab: AdminTab = .command\n    @State private var showsLogoutConfirmation = false",
    "    @State private var selectedTab: AdminTab = .command\n    @State private var commandShowsNestedWorkflow = false\n    @State private var showsLogoutConfirmation = false",
)
replace_once(
    shell,
    "            AdminCommandOrbitDashboard(session: session, languageCode: sessionStore.languageCode)\n                .ignoresSafeArea(.all, edges: .top)",
    "            AdminCommandOrbitDashboard(\n                session: session,\n                languageCode: sessionStore.languageCode,\n                onNavigationDepthChanged: { commandShowsNestedWorkflow = $0 }\n            )\n                .ignoresSafeArea(.all, edges: .top)",
)
replace_once(
    shell,
    "        .safeAreaInset(edge: .bottom, spacing: 0) {\n            V6GlobalTabBar(selectedTab: $selectedTab)\n        }",
    "        .safeAreaInset(edge: .bottom, spacing: 0) {\n            if !(selectedTab == .command && commandShowsNestedWorkflow) {\n                V6GlobalTabBar(selectedTab: $selectedTab)\n            }\n        }",
)
replace_once(
    shell,
    "private struct AdminCommandOrbitDashboard: UIViewControllerRepresentable {\n    let session: AdminSession\n    let languageCode: String\n\n    func makeUIViewController(context: Context) -> AdminCommandOrbitContainerController {\n        AdminCommandOrbitContainerController()\n    }\n\n    func updateUIViewController(_ controller: AdminCommandOrbitContainerController, context: Context) {\n        controller.refresh(session: session, languageCode: languageCode)\n    }\n}",
    "private struct AdminCommandOrbitDashboard: UIViewControllerRepresentable {\n    let session: AdminSession\n    let languageCode: String\n    let onNavigationDepthChanged: (Bool) -> Void\n\n    func makeUIViewController(context: Context) -> AdminCommandOrbitContainerController {\n        let controller = AdminCommandOrbitContainerController()\n        controller.onNavigationDepthChanged = onNavigationDepthChanged\n        return controller\n    }\n\n    func updateUIViewController(_ controller: AdminCommandOrbitContainerController, context: Context) {\n        controller.onNavigationDepthChanged = onNavigationDepthChanged\n        controller.refresh(session: session, languageCode: languageCode)\n    }\n}",
)
replace_once(
    shell,
    "private final class AdminCommandOrbitContainerController: UIViewController, UINavigationControllerDelegate {\n    private let dashboard = PPAdminCreateCommandSpineDashboardController()",
    "private final class AdminCommandOrbitContainerController: UIViewController, UINavigationControllerDelegate {\n    var onNavigationDepthChanged: ((Bool) -> Void)?\n    private let dashboard = PPAdminCreateCommandSpineDashboardController()",
)
replace_once(
    shell,
    "    func navigationController(_ navigationController: UINavigationController,\n                              willShow viewController: UIViewController,\n                              animated: Bool) {\n        applyGlobalNavigationPresentation(to: viewController, in: navigationController)",
    "    func navigationController(_ navigationController: UINavigationController,\n                              willShow viewController: UIViewController,\n                              animated: Bool) {\n        onNavigationDepthChanged?(navigationController.viewControllers.first !== viewController)\n        applyGlobalNavigationPresentation(to: viewController, in: navigationController)",
)
replace_once(
    shell,
    "    func navigationController(_ navigationController: UINavigationController,\n                              didShow viewController: UIViewController,\n                              animated: Bool) {\n        refreshGlobalNavigation()\n    }\n}",
    "    func navigationController(_ navigationController: UINavigationController,\n                              didShow viewController: UIViewController,\n                              animated: Bool) {\n        onNavigationDepthChanged?(navigationController.viewControllers.first !== viewController)\n        refreshGlobalNavigation()\n    }\n}",
)
replace_once(
    shell,
    "            trailingActions: trailingActions(for: viewController),\n            showsContextFilament: true\n        )",
    "            trailingActions: trailingActions(for: viewController),\n            showsContextFilament: false\n        )",
)

# Full-screen legacy routes use the same restrained navigation language.
route = "PurePetsAdmin/Shared/Routing/AdminRoute.swift"
replace_once(
    route,
    "            trailingActions: trailingActions(for: viewController),\n            showsContextFilament: true\n        )",
    "            trailingActions: trailingActions(for: viewController),\n            showsContextFilament: false\n        )",
)

# -----------------------------------------------------------------------------
# Accessory/Food/Live Pet editor: compact dossier rhythm, one persistent save
# action, safe-area docking, and no decorative elevation. Business/form logic is
# untouched.
# -----------------------------------------------------------------------------
accessory = "PurePetsAdmin/AccessorySection/AddAccessoryViewController.m"
replace_once(
    accessory,
    "        [stack.topAnchor constraintEqualToAnchor:header.topAnchor constant:PPSpaceXL],",
    "        [stack.topAnchor constraintEqualToAnchor:header.topAnchor constant:PPSpaceSM],",
)
replace_once(
    accessory,
    "    CGFloat height = MAX(PPSpace4XL, ceil(fittingSize.height));",
    "    CGFloat height = MAX(PPButtonHeightLG, ceil(fittingSize.height));",
)
replace_once(accessory, "    PPApplyElevatedShadow(dock);\n", "")
replace_once(
    accessory,
    "    self.saveDockBottomConstraint = [dock.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor];",
    "    self.saveDockBottomConstraint = [dock.bottomAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.bottomAnchor];",
)
replace_once(
    accessory,
    "    insets.bottom += dockHeight + PPSpaceLG + self.keyboardOverlap;",
    "    insets.bottom += dockHeight + PPSpaceSM + self.keyboardOverlap;",
)
replace_once(
    accessory,
    "    self.baseTableContentInset = UIEdgeInsetsMake(PPSpaceMD, 0, PPSpaceSM, 0);",
    "    self.baseTableContentInset = UIEdgeInsetsMake(PPSpaceXS, 0, PPSpaceSM, 0);",
)
replace_once(
    accessory,
    "    self.tableView.separatorStyle = UITableViewCellSeparatorStyleNone;\n    self.baseTableContentInset",
    "    self.tableView.separatorStyle = UITableViewCellSeparatorStyleNone;\n    if (@available(iOS 15.0, *)) {\n        self.tableView.sectionHeaderTopPadding = PPSpaceSM;\n    }\n    self.baseTableContentInset",
)
replace_once(
    accessory,
    "    if (!self.navigationSaveButton) {\n        self.navigationSaveButton = [self pp_ButtonWithSystemName:@\"checkmark\" action:@selector(onSave)];\n        self.navigationSaveButton.accessibilityLabel = kLang(@\"Save\");\n        self.navigationSaveButton.accessibilityIdentifier = @\"admin-accessory-editor-save\";\n    }\n    [self pp_navBarWithOtherButton:self.navigationSaveButton title:self.title];\n    self.navigationItem.rightBarButtonItem.accessibilityIdentifier = @\"admin-accessory-editor-save\";",
    "    // Long inventory forms use the persistent save dock as the single\n    // primary commit action. Avoid duplicating Save in global navigation.\n    [self pp_navBarWithOtherButton:nil title:self.title];",
)

# -----------------------------------------------------------------------------
# Payments work queue: tighter scan density, calm inline actions, localized
# workflow states, and more useful compact summary/search chrome.
# -----------------------------------------------------------------------------
models = "PurePetsAdmin/Payments/PPPaymentManagementModels.m"
replace_once(
    models,
    "    if (normalized.length == 0) return kLang(@\"PaymentMgmt_WorkflowStatus_Pending\");\n    if ([normalized isEqualToString:@\"paid\"]) return kLang(@\"PaymentMgmt_WorkflowStatus_Paid\");\n    if ([normalized isEqualToString:@\"processing\"]) return PPPaymentAdminDisplayTitleForOrderStatus(@\"processing\");",
    "    if (normalized.length == 0 || [normalized isEqualToString:@\"pending\"] || [normalized isEqualToString:@\"pending_collection\"]) {\n        return kLang(@\"PaymentMgmt_WorkflowStatus_Pending\");\n    }\n    if ([normalized isEqualToString:@\"verification_pending\"]) return PPPaymentAdminDisplayTitleForOrderStatus(@\"verification_pending\");\n    if ([normalized isEqualToString:@\"paid\"]) return kLang(@\"PaymentMgmt_WorkflowStatus_Paid\");\n    if ([normalized isEqualToString:@\"processing\"] ||\n        [normalized isEqualToString:@\"preparing\"] ||\n        [normalized isEqualToString:@\"packed\"] ||\n        [normalized isEqualToString:@\"shipped\"] ||\n        [normalized isEqualToString:@\"shipping\"] ||\n        [normalized isEqualToString:@\"in_transit\"] ||\n        [normalized isEqualToString:@\"out_for_delivery\"] ||\n        [normalized isEqualToString:@\"delivered\"] ||\n        [normalized isEqualToString:@\"completed\"]) {\n        return PPPaymentAdminDisplayTitleForOrderStatus(normalized);\n    }",
)

payments = "PurePetsAdmin/Payments/PPPaymentManagementViewController.m"
replace_once(
    payments,
    "    if ([normalized isEqualToString:@\"verification_pending\"]) return @\"shield.lefthalf.filled\";",
    "    if ([normalized isEqualToString:@\"pending\"]) return @\"clock.fill\";\n    if ([normalized isEqualToString:@\"pending_collection\"]) return @\"banknote.fill\";\n    if ([normalized isEqualToString:@\"verification_pending\"]) return @\"shield.lefthalf.filled\";",
)
replace_once(payments, "    self.tableView.estimatedRowHeight = 124.0;", "    self.tableView.estimatedRowHeight = 108.0;")
replace_once(
    payments,
    "    self.tableView.separatorStyle = UITableViewCellSeparatorStyleNone;\n}",
    "    self.tableView.separatorStyle = UITableViewCellSeparatorStyleNone;\n    if (@available(iOS 15.0, *)) {\n        self.tableView.sectionHeaderTopPadding = PPSpaceSM;\n    }\n}",
)
replace_once(
    payments,
    "    CGFloat vertical = PPSpaceSM;\n    CGFloat searchHeight = PPButtonHeightLG;",
    "    CGFloat vertical = PPSpaceXS;\n    CGFloat searchHeight = MAX(PPTouchTargetMin, PPButtonHeightMD);",
)
replace_once(
    payments,
    "    search.textField.placeholder = kLang(@\"PaymentMgmt_Search_Placeholder\");\n    search.textField.textAlignment",
    "    NSString *searchPlaceholder = kLang(@\"PaymentMgmt_Search_Placeholder\");\n    search.textField.placeholder = searchPlaceholder;\n    search.textField.textColor = [UIColor ppTextPrimary];\n    search.textField.tintColor = [UIColor ppPrimary];\n    search.textField.attributedPlaceholder = [[NSAttributedString alloc] initWithString:searchPlaceholder\n                                                                            attributes:@{NSForegroundColorAttributeName: [UIColor ppTextTertiary]}];\n    search.textField.textAlignment",
)
replace_once(
    payments,
    "            [AlertHelper showErrorIn:self title:kLang(@\"Error\") subtitle:error.localizedDescription ?: kLang(@\"PaymentMgmt_Error_UpdateOrder\")];",
    "            [AlertHelper showErrorIn:self title:kLang(@\"Error\") subtitle:kLang(@\"PaymentMgmt_Error_UpdateOrder\")];",
)
replace_once(payments, "    cell.detailTextLabel.text = [parts componentsJoinedByString:@\"\\n\"];", "    cell.detailTextLabel.text = [parts componentsJoinedByString:@\" • \"];")
replace_once(
    payments,
    "    header.textLabel.font = [Styling fontMedium:14];",
    "    header.textLabel.font = [[UIFontMetrics metricsForTextStyle:UIFontTextStyleSubheadline] scaledFontForFont:[Styling fontMedium:14]];\n    header.textLabel.adjustsFontForContentSizeCategory = YES;",
)

cell = "PurePetsAdmin/Payments/PPPaymentManagementRecordCell.m"
replace_once(
    cell,
    "    contentStack.axis = UILayoutConstraintAxisVertical;\n    contentStack.spacing = PPSpaceMD;",
    "    contentStack.axis = UILayoutConstraintAxisVertical;\n    contentStack.spacing = PPSpaceSM;",
)
replace_once(
    cell,
    "        [contentStack.topAnchor constraintEqualToAnchor:_surfaceView.topAnchor constant:PPSpaceBase],\n        [contentStack.leadingAnchor constraintEqualToAnchor:_surfaceView.leadingAnchor constant:PPSpaceBase],\n        [contentStack.trailingAnchor constraintEqualToAnchor:_surfaceView.trailingAnchor constant:-PPSpaceBase],\n        [contentStack.bottomAnchor constraintEqualToAnchor:_surfaceView.bottomAnchor constant:-PPSpaceBase],",
    "        [contentStack.topAnchor constraintEqualToAnchor:_surfaceView.topAnchor constant:PPSpaceMD],\n        [contentStack.leadingAnchor constraintEqualToAnchor:_surfaceView.leadingAnchor constant:PPSpaceBase],\n        [contentStack.trailingAnchor constraintEqualToAnchor:_surfaceView.trailingAnchor constant:-PPSpaceBase],\n        [contentStack.bottomAnchor constraintEqualToAnchor:_surfaceView.bottomAnchor constant:-PPSpaceMD],",
)
replace_once(
    cell,
    "    if (prominentAction) {\n        _actionButton.backgroundColor = resolvedActionTint;\n        _actionButton.layer.borderColor = UIColor.clearColor.CGColor;\n        [_actionButton setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];\n    } else {",
    "    if (prominentAction) {\n        // In a repeated work queue, keep the next action visually clear without\n        // turning every row into a competing solid CTA. Confirmation remains\n        // mandatory in the controller before any mutation is executed.\n        _actionButton.backgroundColor = [resolvedActionTint colorWithAlphaComponent:0.11];\n        _actionButton.layer.borderColor = [resolvedActionTint colorWithAlphaComponent:0.22].CGColor;\n        [_actionButton setTitleColor:resolvedActionTint forState:UIControlStateNormal];\n    } else {",
)

print("Applied runtime screenshot V6 pass.")
