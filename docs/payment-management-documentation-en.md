# PurePetsAdmin Payment Management Documentation

## 1. Overview

This documentation describes the Payment Management work completed in the `PurePetsAdmin` app, the supporting Firebase hardening, the Admin-side safety controls, and the follow-up build stabilization work that was required to keep the Admin app moving toward a production-ready state.

Scope was intentionally limited to the Admin app.

## 2. Main Outcome

A dedicated Payment Management section was added to the Admin app so administrators can:

- View payment-related orders
- Search by order ID, user, and payment method
- Filter by workflow status, date range, and payment type
- Open a full details page for a payment/order
- Review payment timeline and request history
- Approve eligible orders
- Cancel eligible orders
- Review and resolve refund/return requests
- Track pending, paid, failed, cancelled, refunded, and partially refunded states
- Record admin audit history for sensitive actions

## 3. New Admin Payment Module

The new Admin payment module lives under:

- `PurePetsAdmin/PurePetsAdmin/Payments/PPPaymentManagementModels.h`
- `PurePetsAdmin/PurePetsAdmin/Payments/PPPaymentManagementModels.m`
- `PurePetsAdmin/PurePetsAdmin/Payments/PPPaymentManagementService.h`
- `PurePetsAdmin/PurePetsAdmin/Payments/PPPaymentManagementService.m`
- `PurePetsAdmin/PurePetsAdmin/Payments/PPPaymentManagementViewController.h`
- `PurePetsAdmin/PurePetsAdmin/Payments/PPPaymentManagementViewController.m`
- `PurePetsAdmin/PurePetsAdmin/Payments/PPPaymentDetailsViewController.h`
- `PurePetsAdmin/PurePetsAdmin/Payments/PPPaymentDetailsViewController.m`

### 3.1 Models added

The payment models now cover:

- `PPPaymentManagementFilters`
  - Search text
  - Workflow status filter
  - Payment type filter
  - Date range filter

- `PPPaymentAdminRecord`
  - Order identity and user summary
  - Payment provider and payment type
  - Raw order/payment status
  - Refund and return signals
  - Item snapshots
  - Shipping snapshot
  - Inventory deduction/restock flags
  - Request summaries
  - Timeline events
  - Audit trail entries

- `PPPaymentAdminSupportRequest`
  - Refund/return/support request details
  - Request status
  - Final resolution
  - Attachments
  - Review metadata
  - Resolution metadata
  - Request events

- `PPPaymentAdminTimelineEvent`
  - Order/request event history

- `PPPaymentAdminAuditEntry`
  - Admin action trail with before/after state snapshots

### 3.2 Workflow states supported

The payment management flow currently handles:

- `pending`
- `paid`
- `failed`
- `cancelled`
- `refunded`
- `partially_refunded`
- request-side states such as:
  - `pending_review`
  - `approved`
  - `rejected`
  - `completed`
  - `closed`

## 4. Admin UI Delivered

### 4.1 Payment list screen

`PPPaymentManagementViewController` provides:

- Search input with debounced reload
- Filter action sheet
- Status filter
- Payment method filter
- Date range filter
- Reset filters action
- Summary section showing payment counts and active filter summary
- Paginated payment list
- Pull to refresh
- Proper loading, empty, and error states

### 4.2 Payment details screen

`PPPaymentDetailsViewController` provides:

- Overview section
- Admin action section
- Items section
- Requests section
- Timeline section
- Audit Trail section
- Refresh flow for the selected order

### 4.3 Admin action UX protections

Sensitive actions are not one-tap destructive actions. The UI includes:

- Confirmation dialogs before applying approve/cancel/request-resolution actions
- Required admin note for sensitive actions
- In-flight action locking to reduce duplicate submissions
- Success and error feedback through HUD/alerts

## 5. Firebase Integration and Data Flow

The Admin app integrates directly with Firebase Firestore for payment operations.

### 5.1 Collections and subcollections used

The implemented Admin flow works with:

- `Orders/{orderId}`
- `Orders/{orderId}/events/{eventId}`
- `Orders/{orderId}/requests/{requestId}`
- `Orders/{orderId}/requests/{requestId}/events/{eventId}`
- `AdminAuditLogs/{auditId}`

### 5.2 Read flows

The service loads:

- Orders from `Orders`
- Related request summaries from `Orders/{orderId}/requests`
- Timeline events from `Orders/{orderId}/events`
- Request events from `Orders/{orderId}/requests/{requestId}/events`
- Admin audit entries from `AdminAuditLogs`

### 5.3 Write flows

The service safely writes:

- Approved order state updates
- Cancelled order state updates
- Request status updates
- Refund and partial refund metadata
- Return completion metadata
- Order timeline events
- Request timeline events
- Admin audit logs
- Inventory deduction/restock updates when required

## 6. Production Safety Controls Added

### 6.1 Permission protection

Admin payment actions are protected in code by checking the current admin permissions before:

- listing payments
- loading full payment details
- approving an order
- cancelling an order
- resolving a refund/return request

Current code accepts payment-management access through:

- `ManageStore`
- `AdminAll`

### 6.2 Firestore rules hardening

`PurePetsAdmin/firestore.rules` was updated so payment writes are restricted to safe, explicit fields.

For `Orders/{orderId}`:

- create/delete is denied
- update is allowed only for payment-management admins
- immutable fields such as `orderId`, `userId`, `items`, totals, currency, and shipping snapshot must remain unchanged
- only approved payment-operation fields may change

For `Orders/{orderId}/requests/{requestId}`:

- create/delete is denied
- update is allowed only for safe request-resolution fields
- immutable request identity and payload fields must remain unchanged

For payment timeline events:

- create-only
- schema validation enforced

For `AdminAuditLogs`:

- create-only
- schema validation enforced
- read access restricted to admins / payment managers

### 6.3 Invalid transition prevention

The payment models and service now block invalid state changes such as:

- approving an already paid/cancelled order
- cancelling an order from a non-cancellable state
- refunding non-refund request types
- completing returns before approval
- applying unsupported request state transitions

### 6.4 Race-condition and duplicate-update protection

Sensitive mutations run inside Firestore transactions so state is re-read at execution time before mutation.

This reduces the risk of:

- stale admin decisions
- double approval
- duplicate refund logic
- inventory drifting from final order state

### 6.5 Audit trail

Every sensitive payment action now writes an admin audit entry containing:

- action name
- area = `payments`
- entity type / entity id
- order id
- request id when relevant
- admin uid
- admin name
- admin note
- before-state snapshot
- after-state snapshot
- created timestamp

## 7. Inventory Safety

The payment service now coordinates inventory changes with order/payment changes.

### 7.1 On approval

When an eligible order is approved:

- order status moves to `paid`
- verification status becomes `verified`
- `paidAt` is set if missing
- inventory is deducted only if it has not already been deducted
- inventory deduction failure aborts the entire transaction

### 7.2 On cancellation

When an eligible order is cancelled:

- order status moves to `cancelled`
- cancellation metadata is recorded
- inventory is restocked only when necessary

### 7.3 On return completion

When a return request is completed:

- request resolution is recorded
- return status is updated
- returned items are restocked safely based on clamped request item quantities

## 8. Refund and Return Handling

### 8.1 Refund handling

The implemented flow supports:

- full refund
- partial refund

Refund processing updates:

- request status
- final resolution
- order `refundStatus`
- order `refundAmount`
- order `refundedAt`

Partial refund safety:

- amount must be greater than zero
- amount must be less than total order value

### 8.2 Return handling

The implemented flow supports:

- reviewing return requests
- approving/rejecting requests
- completing eligible return requests
- restocking returned items on completion
- updating `returnStatus` on the order

## 9. Dashboard Integration

The Admin dashboard now includes a Payment Management entry point:

- Title: `Payment Management`
- Subtitle: `Review orders, refunds, returns, and payment history`

This entry pushes `PPPaymentManagementViewController`.

## 10. Tests Added

`PurePetsAdminTests/PurePetsAdminTests.m` now includes payment-focused unit tests for:

- workflow status selection
- refund signal priority
- approval rules
- refund action restrictions
- return completion rules

These tests validate important business logic, especially transition safety.

## 11. Additional Admin Build Hardening Performed

While integrating the payment module, the Admin app exposed older Firebase integration problems outside the new payment code. To keep the Admin app moving toward a releasable state, additional Admin-side hardening was completed.

### 11.1 Firebase compatibility header

Added:

- `PurePetsAdmin/PurePetsAdmin/PPFirebaseCompat.h`

Purpose:

- bridge Objective-C usage against Firebase SDK surfaces that were causing compatibility issues in this workspace
- provide missing declarations used by older Admin source files
- normalize access to Firestore/Auth/Functions/Storage symbols used across the Admin app

### 11.2 Admin-side Firebase import cleanup

A set of legacy Admin files were updated to use the compatibility layer instead of brittle direct imports.

This included fixes in areas such as:

- users/permissions management
- admin login
- banners
- accessories
- styling/storage usage
- basic Firestore-backed models

### 11.3 Banner compile blocker fixes

Additional fixes applied during the continuation pass:

- `PPBannerViewModel.m` now explicitly imports `PPFirebaseCompat.h` so `FIRTimestamp` usage is valid
- `PPBannersManager.h` now exposes Firebase listener types through the compatibility header
- `PPBannersListVC.m` now explicitly imports the Firebase compatibility header and banner manager header so listener removal compiles cleanly

These changes were required because legacy Admin banner code was blocking full project compilation before the new payment section could be fully validated in a whole-app build.

## 12. Files Affected by the Payment Work

Core payment files added:

- `PurePetsAdmin/PurePetsAdmin/Payments/PPPaymentManagementModels.h`
- `PurePetsAdmin/PurePetsAdmin/Payments/PPPaymentManagementModels.m`
- `PurePetsAdmin/PurePetsAdmin/Payments/PPPaymentManagementService.h`
- `PurePetsAdmin/PurePetsAdmin/Payments/PPPaymentManagementService.m`
- `PurePetsAdmin/PurePetsAdmin/Payments/PPPaymentManagementViewController.h`
- `PurePetsAdmin/PurePetsAdmin/Payments/PPPaymentManagementViewController.m`
- `PurePetsAdmin/PurePetsAdmin/Payments/PPPaymentDetailsViewController.h`
- `PurePetsAdmin/PurePetsAdmin/Payments/PPPaymentDetailsViewController.m`

Supporting integration changes:

- `PurePetsAdmin/PurePetsAdmin/AdminDashboardViewController.m`
- `PurePetsAdmin/PurePetsAdminTests/PurePetsAdminTests.m`
- `PurePetsAdmin/firestore.rules`
- `PurePetsAdmin/PurePetsAdmin.xcodeproj/project.pbxproj`
- `PurePetsAdmin/PurePetsAdmin.xcodeproj/xcshareddata/xcschemes/PurePetsAdmin.xcscheme`
- `PurePetsAdmin/PurePetsAdmin/PPFirebaseCompat.h`

Admin-side follow-up compile stabilization included changes in additional legacy Admin files as needed to keep the app buildable.

## 13. Verification Performed

The following verification work was completed:

- confirmed the Payment Management module exists and is wired into the Admin dashboard
- confirmed Admin payment service enforces permissions before reads/writes
- confirmed transaction-based writes exist for approve/cancel/request resolution
- confirmed audit logging and timeline writes are implemented
- confirmed Firestore rules restrict payment mutations to allowed fields
- confirmed payment business-logic tests exist
- fixed additional Admin compile blockers around Firebase compatibility and banner listener/timestamp usage

## 14. Current Verification Boundary

Full local end-to-end build verification on this machine is currently blocked by environment issues, not by the payment implementation itself.

Current machine-level blockers observed during `xcodebuild`:

- CoreSimulator service instability
- sandboxed DerivedData path issues, worked around with `/tmp`
- `ibtool` storyboard compilation failure because `iOS 26.2 Platform Not Installed`

Because storyboard compilation stops the full app build early, this machine cannot yet prove there are zero later compile/link issues in the rest of the legacy Admin app after the storyboard phase. The payment code and the immediate Firebase/banner blockers were inspected and advanced, but whole-app verification remains environment-limited.

## 15. Remaining Risks

The main remaining risks are:

- local environment risk: the host Xcode installation is missing the required iOS platform/runtime for storyboard compilation
- legacy Admin app risk: once the environment issue is removed, additional compile issues may still surface in unrelated old modules because the project is large and historically inconsistent
- operational risk: production use still depends on real Firestore data shape matching the expected `Orders`, `requests`, `events`, and inventory documents

## 16. Recommended Next Step

To finish release-level verification:

1. Install the required iOS platform/runtime used by the current Xcode toolchain.
2. Re-run a full Admin build.
3. Run Admin tests.
4. Perform manual payment workflow QA against a staging Firebase project:
   - approve pending order
   - cancel eligible order
   - approve refund request
   - partial refund
   - approve and complete return
   - verify audit logs and timeline events

## 17. Final Summary

What was added:

- a complete Admin Payment Management section
- payment list, filters, details, and request handling
- approve/cancel/refund/return management flows
- audit trail and timeline support
- Admin dashboard entry
- Firestore security rules for safe payment operations
- unit tests for core payment workflow logic

What was fixed:

- Admin Firebase integration gaps that blocked payment-related compilation
- Objective-C compatibility issues around Firebase Auth/Firestore/Functions/Storage access
- legacy Admin banner compile blockers discovered while validating the app

Remaining risk:

- full whole-app build verification is currently blocked by local Xcode/platform environment issues, specifically storyboard compilation against an unavailable iOS platform
