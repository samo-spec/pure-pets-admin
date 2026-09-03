# Pure Pets Admin: Multi-Branch Operational Guide

> **Target Surface:** `Pure Pets Admin/` (iOS Staff App)  
> **Primary Language:** Arabic (RTL) · Secondary: English (LTR)

---

## 1. Overview

The Pure Pets Admin iOS application operates under a strict **Branch Context Architecture**. Staff actions (inventory viewing, stock transfers, counter receipts, payments, and financial summaries) are scoped to the **active working branch**.

---

## 2. Core Components

### A. Context Manager (`PPBranchContextManager`)
- **Singleton Authority:** `[PPBranchContextManager sharedManager]`
- **Persistence:** Securely caches user branch selection in `NSUserDefaults` under `PPAdminActiveBranchID_<uid>`.
- **Notifications:**
  - `PPActiveBranchDidChangeNotification`: Broadcast whenever the working branch changes.
  - `PPAvailableBranchesDidChangeNotification`: Broadcast when authorized branches are loaded or refreshed.
- **Auto-Selection Logic:**
  1. Checks cached selection for the active staff UID.
  2. If none, falls back to `staffDoc.defaultBranchID`.
  3. If staff is assigned to exactly **one branch**, auto-selects that branch immediately.
  4. If staff has **multiple assigned branches** and no active selection, sets `needsBranchSelection = YES`.

### B. SwiftUI Bridge (`BranchContextStore`)
- `@MainActor` `ObservableObject` exposing `@Published` properties:
  - `activeBranch: PPBranchModel?`
  - `availableBranches: [PPBranchModel]`
  - `isGlobal: Bool`
  - `needsBranchSelection: Bool`
  - `currentBranchDisplayName: String`
- Methods: `selectBranch(_:)`, `selectBranch(id:)`, `reload()`, `clear()`.

### C. Post-Login Branch Selection Gate (`PPBranchSelectionGateView`)
- **Presentation Trigger:** Shown automatically as a `.fullScreenCover` over `AdminAppRoot` when `BranchContextStore.shared.needsBranchSelection` is `true`.
- **Enforcement:** `interactiveDismissDisabled(true)` prevents dismissing the view without choosing an authorized branch.
- **Craft Details:** Premium card list with branch code badges, contact information, default branch pills, and tactile haptic feedback.

### D. Navigation Switcher Bar (`PPAdminBranchSwitcherBar`)
- Rendered in navigation headers across `AdminModuleListView` (Work, Operations, Customers) and `AdminMoreView`.
- Displays the active branch name, building glyph, and code badge.
- Tapping opens the interactive switcher sheet allowing staff with multiple branch authorizations to switch context on the fly.

### E. Native UIKit Hero Integration (`AdminDashboardViewController`)
- Top hero action stack contains `heroBranchButton` alongside the profile, language, and logout controls.
- Tapping presents a native `UIAlertControllerStyleActionSheet` listing permitted branches.
- Selecting a new branch posts `PPActiveBranchDidChangeNotification`, instantly refreshing the live badge and table data without re-logging.

---

## 3. Staff RBAC Matrix in Admin App

| Staff Role | Key Permissions | Branch Context Scope |
|---|---|---|
| **Super Admin / Owner** | All permissions | Global access with ability to switch to any active branch |
| **Branch Manager** | POS, Stock, Local Accounting, Dispatch | Assigned branch(es) |
| **Accountant** | Accounting, Payments, COD Reconciliation, Reports | Assigned branch(es) or Global |
| **Warehouse** | Stock Manage, Delivery Dispatch, Categories | Assigned branch(es) |
| **Sales** | POS Sell, POS History, Stock View | Assigned branch(es) |

---

## 4. Verification & Testing

Unit tests in `PurePetsAdminTests/PurePetsAdminTests.m`:
- `testBranchModelSerializationAndEnterpriseFields`: Validates `PPBranchModel` dictionary parsing and serialization of enterprise fields (`managerId`, `operatingHours`, `taxNumber`, `crNumber`).
- `testStaffDocMultiBranchScopeAndPermissions`: Validates multi-branch access control and granular branch-specific overrides on `PPStaffDoc`.
- `testStaffDocLocalizedRoleNames`: Validates role string normalization and localized role titles.
