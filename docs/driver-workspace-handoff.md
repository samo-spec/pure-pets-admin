# Admin driver workspace — implementation handoff

Date: 2026-10-23. Status: source implemented and backend contracts tested; native build, device acceptance and production activation are unverified. No deployment or production permission changes were performed.

## Product behavior

An authorized workforce driver lands in **My deliveries / توصيلاتي** after Admin login. The native UIKit run sheet has personal active work, eligible new deliveries, and finished work. A delivery detail keeps pickup, drop-off, customer contact and the next permitted physical action together. Directions open Apple Maps using the authorized address. Availability changes only the driver's own online state.

The existing Admin shell owns navigation, session changes and permission filtering. Drivers receive the other modules for which their session has explicit permissions. The built-in driver role does not grant dashboard, inventory, financial administration, dispatch, staff administration, or Pro provider access. Personal account and permitted notification destinations remain available.

New work withholds recipient identity, phone, exact street address and cash details until assignment. Claims bind to the authenticated UID. The interface makes no geographic sequencing or route-optimization claim; the focused heading is “ON YOUR RUN / ضمن مهامك.” Passive refresh defers while additional pages or active scrolling would be disrupted. Pull-to-refresh deliberately reloads the first page.

## Authority and integration

Infra remains the schema, lifecycle, authorization, audit and notification owner.

| Contract | Implementation |
| --- | --- |
| Driver role | `delivery_driver`, with exactly `delivery.tasks.manage` and `notifications.view` |
| Driver identity | Active `UsersCol` staff account and canonical active `staff_users` authorization |
| Fleet membership | Active `driver` membership in the existing official `deliveryCompanies/{companyId}/members/{uid}` hierarchy |
| Scope | Existing branch/region/agent authorization, exact assignment and carrier ownership |
| New read callable | `getDriverDeliveryWorkspace` |
| New mutation callables | `executeDriverDeliveryTask`, `setDriverDeliveryAvailability` |
| New event triggers | `onDriverFulfillmentTaskWritten`, `onDriverCompanyTaskWritten` |
| V1 order authority | Existing `executeFulfillmentV1DeliveryCommand` |
| Legacy order authority | Existing company-delivery command engine, through a server-only self-driver adapter |
| Native routes | `driverWorkspace`, `driverTask(AUTHORITY:taskID)` |
| Notification route | `driver_task`, with `taskId` and `authority` |
| Notification target | V2 `staff:{uid}`, `admin_ios`, `staff.delivery` |

The existing authorized fleet invitation workflow accepts a staff UID, email or phone and creates membership; it does not require the target to hold a Pro feature. Membership and staff permission remain separate prerequisites. The new screen cannot enroll itself, grant permissions, resume dispatcher-suspended assignments or increase capacity.

Every task mutation rechecks active identity, membership, scope, assignment, lifecycle state and revision inside the canonical transaction. Competing claims cannot assign the same task twice. Canonical writes, audit, workload, parent projection and command receipts remain atomic. Public provider/courier callers cannot inject the internal workforce capability.

Cash confirmation uses the canonical order amount/currency and rejects an amount that changed after the driver viewed it. Multi-item cash collection validates every payable child and produces one receipt. A stable anchor command allows retrying a lost response after the task's state changes. The UI retains an uncertain command ID for retry and disables obsolete actions while authoritative state reloads.

List queries have bounded pages and document-ID cursors. Parent, membership, branch and workload reads are reused only within a single read request; mutations never use those caches. Firestore/Storage rule predicate behavior is unchanged; only generated catalog hash pins changed.

## Notifications

Committed assignment/status changes and eligible new work enqueue deterministic delivery outbox entries with audit records. The existing durable V2 outbox/dispatcher owns delivery and retries. Workforce notifications target Admin rather than Pro. Device registration accepts `staff.delivery` for the new permission plus `notifications.view`; it does not grant order-wide, payment, support or provider notification scopes.

Foreground notifications refresh an eligible visible workspace. Notification taps and inbox actions open the guarded task route. A launch-time route can survive the first login, while sign-out from an established session clears protected routes. Task detail reauthorizes and clears data when access is denied. Notification send/composer controls require their own grant. The driver utility can request iOS notification permission or open system settings when disabled.

Source and in-memory tests establish the route/actor/scope contracts. They do **not** establish APNs delivery, live device registration, inbox delivery, deployed functions or receipt on a physical iPhone.

## Localization and native behavior

- 69 new driver/role localization entries have matching Arabic and English keys and format placeholders.
- Logical leading/trailing constraints and the existing `Language` semantics/alignment helpers are used.
- Brand fonts scale through Dynamic Type; addresses and labels wrap. Accessibility text sizes stack the lane controls vertically.
- Header and secondary actions scroll, with readable-width layout on iPad and one primary action near the bottom safe area.
- VoiceOver labels group each task; completion has an accessibility announcement. No continuous decorative animation is introduced.
- Semantic product colors adapt to supported light/dark appearance. Physical-device contrast, layout, VoiceOver and Reduce Motion behavior have not been observed.

## Important source files

Admin:

- `PurePetsAdmin/Delivery/PPDriverWorkspaceViewController.h/.m` — run sheet, task detail, availability, route parser and recovery states.
- `PurePetsAdmin/Delivery/PPDriverWorkspaceService.h/.m` — callable service boundary.
- `PurePetsAdmin/App/AdminTab.swift`, `AdminAppShell.swift`, `AdminAppRoot.swift`, `AdminRouteDestinationView.swift` — driver landing and session/navigation integration.
- `PurePetsAdmin/Shared/Routing/AdminRoute.swift`, `PPAdminRouteFactory.m` — guarded route declarations and native factory.
- `PurePetsAdmin/Features/CommandCenter/CommandCenterState.swift` — do not load aggregate dashboard data for an unauthorized driver session.
- `PurePetsAdmin/AppDelegate.m`, `SceneDelegate.m`, `NotificationsSection/NotificationModel.m`, `NotificationDetailViewController.m`, `NotificationsListViewController.m` — registration, foreground refresh, cold/warm route and inbox integration.
- `PurePetsAdmin/ar.lproj/Localizable.strings`, `en.lproj/Localizable.strings` — localized copy.
- `PurePetsAdmin.xcodeproj/project.pbxproj`, `PurePetsAdmin/PurePetsAdmin-Bridging-Header.h` — target membership and UIKit bridge.
- `PurePetsAdmin/UsersSection/SecFil/PPStaffAuthCatalog.generated.h/.m` — generated role/permission catalog.

Infra:

- `functions/deliveryDriverAuthorization.js`, `deliveryDriverWorkspace.js` — explicit workforce authority, projections, commands and notification triggers.
- `functions/deliveryCommandCenter.js`, `fulfillmentOrders.js` — narrow integration with existing engines and durable outbox.
- `functions/notificationsV2/callables.js`, `functions/index.js` — registration policy and canonical lazy exports.
- `iam/policy-catalog.json`, `operation-manifest.json`, `consumer-checkouts.json` — canonical role, permission, function metadata and generated artifact pins.
- `functions/generated/iamCatalog.js`, `iamOperations.js`, `public/assets/js/lib/permissions.generated.js`, `docs/iam/IAM_CATALOG.md`, `ADR-0001-canonical-iam-v2-contract.md`, `firestore.rules`, `storage.rules` — generated contracts and hash alignment.
- `scripts/generate-iam.js` — removes generated markdown trailing whitespace.
- `functions/tests/deliveryDriverWorkspace.test.js`, `deliveryCommandCenter.test.js`, `iamParity.test.js` — integration and canonical-role assertions.

Console changes are limited to generated IAM artifacts: `src/constants/generated/iamCatalog.ts` and `public/assets/js/lib/permissions.generated.js`. Existing fleet and staff-management workflows are reused.

## Validation performed

The following ten Infra suites passed locally with Node v26.7.0. The deployment engine is Node 22, which was not available at the checked standard local paths.

1. `deliveryDriverWorkspace.test.js`: 21 integration cases, including identity/scope/account negatives, ownership conflicts, public capability-injection rejection, claim races, audit rollback, stale revisions, cash snapshot/replay, multi-child payment, availability limits, V2 routing, pagination, legacy capacity and rejection of fabricated proof.
2. `deliveryCommandCenter.test.js`.
3. `deliveryFulfillmentAcceptance.test.js`.
4. `fulfillmentV1DeliveryLifecycle.test.js`: pure assertions; emulator portion not requested.
5. `companyDeliveryNotificationRouting.test.js`.
6. `notificationsV2ClientRegistrationContracts.test.js`.
7. `notificationTargetResolver.test.js`.
8. `iamPolicyContract.test.js`.
9. `iamParity.test.js`: 9/9 groups; 16 roles, 169 permissions; Console/Admin generated parity.
10. `proformaDeploymentDiscovery.test.js`: real Firebase SDK source discovery, 336 registered endpoints; no deployment.

Also passed: `node scripts/generate-iam.js --verify`, Swift frontend syntax parsing for changed Swift files, `plutil -lint` for both localization files and the Xcode project, localization key/placeholder checks, Objective-C source membership checks and `git diff --check`.

An independent source reviewer found no critical/high issue in the reviewed path and confirmed the follow-up pagination, priority-label, loading, first-login routing and notification visibility corrections. SwiftyMax V7 compared a personal run sheet with a map-first alternative and independently selected the run sheet on source/product grounds. Its formal record is valid but **not ready/certified** because native visual/interaction evidence and complete verified proof capture are unavailable. No numerical visual-quality claim is made.

Local logs, baseline snapshots and the V7 source record are in `/tmp/purepets-driver-workspace-20261022`. Those are local task artifacts, not deployed evidence. Earlier staff/floating-bar edits and the preexisting `iamCustomRoles.js` change were preserved; concurrent POS/Console work was not changed by this task.

## Release boundaries and remaining work

1. **Required delivery proof:** legacy jobs requiring a photo, signature or verified OTP show an assistance state. The new screen does not capture/finalize that evidence. It never accepts client-supplied “OTP verified” or arbitrary proof URLs. Those jobs require the existing authorized dispatch workflow; trustworthy driver proof capture needs an additional backend/storage contract before this can be called a complete proof-capable driver release.
2. **Task scope:** this workspace handles order-backed Fulfillment V1 and legacy company deliveries. Hotel-stay transport and third-party provider workflows retain their existing owners.
3. **Native gates:** the user's AGENTS policy forbids native builds without explicit permission. No Xcode build, install, Simulator, physical-device render, VoiceOver run, accessibility measurement or performance trace was performed. When authorized, use only the approved connected iPhone 13 Pro Max and default Xcode DerivedData workflow.
4. **Production activation:** nothing was deployed, no driver grants were changed, and no live notification was sent. A release must coordinate the canonical IAM catalog/hash and authorization projections, relevant existing engine/outbox exports, new exports, and Admin/Console artifacts; then grant the driver role and official-fleet membership through the existing authorized management workflow. A production-shaped driver account and physical-device delivery/notification smoke test remain required.

Do not describe source presence, a unit test, Firebase SDK discovery or Swift parsing as a native build, deployment, live push or release-quality certification.
