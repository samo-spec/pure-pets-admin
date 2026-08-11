# Pure Pets Admin Login and Command Center Handoff

This is the single phase-updated handoff for the Login and Home/Dashboard replacement.

> Ecosystem continuation note: `docs/COMMAND_CENTER_ECOSYSTEM_V3_HANDOFF.md` is the
> current handoff for the bounded Command Center child-workflow redesign. The
> normal root now uses `AdminAppRootHostingController`; the legacy root is an
> explicit `PP_ADMIN_LEGACY_ROOT` rollback seam. Native proof remains blocked.

## Phase 1 - Target Freeze

Status: `PASS` for source freeze; native build/runtime evidence is `UNVERIFIED`.

- Original request: replace Pure Pets Admin Login and Home/Dashboard with SwiftUI, keep one root session owner, preserve production auth/IAM/backend/navigation, switch only after validation, then retire legacy Login/Dashboard and migration code.
- Repository: `Pure Pets Admin`, branch `main`, baseline `60fea8c`, clean working tree at intake.
- Platform: iOS/iPadOS, deployment target 15.0 for the app, Swift 6.0, device families iPhone and iPad.
- Connected physical devices: iPhone on iOS 26.5.2; offline iPad and iPhone 12 Pro Max.
- Build restriction: repository policy forbids `xcodebuild`; simulator evidence is forbidden; default Xcode DerivedData only. Compile, device launch, VoiceOver, RTL, motion, and performance gates are therefore `UNVERIFIED` in this workflow.
- Scope: app root/session state, new SwiftUI Login, authenticated shell, Command Center, command routing bridge, command data aggregation, localization, and legacy Login/Dashboard retirement when source gates close.
- Exclusions: no backend schema changes, no Firebase rule/function changes, no duplicate domain screens, no Home Control feature removal, no auth/IAM replacement, no App Check weakening, no production deployment.
- Authority: Infra/backend contracts; `PPStaffAuth`, `RPManager`, `FUManager`, `UserManager`, `AppManager`, existing domain services, `SceneDelegate`, push/payment route handlers, `Language`, and existing UIKit destination controllers.
- Mode: `redesign` with an ownership migration seam.
- Acceptance: one root session state; Login changes session rather than presenting Home; Command Center loads real service data; five authenticated shell tabs; existing routes remain reachable; logout, language, push payment route, and Google callback remain preserved; exactly one active root/navigation/session owner.

## Phase 2 - Dependency Map

```text
CurrentAppRoot: SceneDelegate
├── LegacyLogin: AdminLoginViewController
├── CurrentSwiftUILogin: PPProLoginHostingController
│   └── AuthPipeline: PPProLoginCoordinator
├── LegacyHome: AdminDashboardViewController
├── AuthService: FUManager + FirebaseAuth
├── SessionStore: UserManager + FUManager auth listener
├── PermissionService: canonical `PPStaffAuth` (`staff_users/{uid}`) + RPManager + UserModel compatibility projection
├── Router: SceneDelegate + AdminDashboardViewController route factory logic
├── BackendServices: payment, fulfillment, delivery, provider, POS, accounting, notifications
└── SharedDependencies: Language, Styling, PPDesignTokens, App Check, push/deep-link handlers
```

Directly coupled contracts inspected:

- `AppDelegate.m`: Firebase/App Check setup, notification registration, iOS 12 fallback root.
- `SceneDelegate.m`: auth routing, root swapping, tabs, payment push routing, language rebuild, Google URL callback.
- `PPProLoginCoordinator.m`: email/Google/biometric sign-in, remember-me keys, retry, App Check failures, canonical `staff_users` staff gate, cache, auth-change notification.
- `PPStaffAuth.m`: canonical `staff_users/{uid}` staff authority, status, role, permissions, scope, workspace access.
- `UserManager.m`: cache/listener ownership and notification-safe logout barrier.
- `AdminDashboardViewController.m`: permission exposure, route mapping, count listeners, language/logout, legacy UI.
- Command services: `PPPaymentManagementService`, `PPFulfillmentService`, `PPDeliveryService`, `PPProviderService`.
- Localization: Arabic and English `Localizable.strings`, `Language` singleton, Beiruti fonts.

## Phase 3 - Behavior Ledger

| ID | Category | Source owner/evidence | Preserved target behavior | Target owner | Verification | Status |
|---|---|---|---|---|---|---|
| B01 | Launch/root | `SceneDelegate` splash/auth routing | restoring, unauthenticated, authenticated states | `AdminSessionStore` + `AdminAppRoot` | source review; device launch pending | `UNVERIFIED` |
| B02 | Email auth | `PPProLoginCoordinator signInWithEmail` | same validation, retry, App Check handling, user-doc ensure, staff gate | existing coordinator via `AdminAuthenticationService` | source seam | `PASS` |
| B03 | Google auth | coordinator + `SceneDelegate openURLContexts` | same provider callback and cancellation handling | existing coordinator + SceneDelegate URL callback | source seam | `PASS` |
| B04 | Biometric | coordinator + `PPBiometric` | same stored credentials and disable-on-invalid-credential policy | existing coordinator | source seam | `PASS` |
| B05 | IAM gate | `PPStaffAuth canAccessStaffWorkspace` | canonical `staff_users/{uid}` record must be exact `active` and include `dashboard.view`; no email-role shortcut | `AdminSessionStore` using existing authority | source seam | `PASS` |
| B06 | Session cache | `UserManager`, `FUManager` | current user/cache remains established before authenticated shell | existing services | source seam | `PASS` |
| B07 | Logout | `UserManager signOutWithCompletion` | notification-device deactivation barrier, cache/listener cleanup, auth notification | `AdminSessionStore` delegates to UserManager | source seam; runtime pending | `UNVERIFIED` |
| B08 | Permission exposure | dashboard permission checks | routes visible only when existing permission keys pass | `AdminSession` + shell/command models | source comparison | `PASS` |
| B09 | Backend authorization | existing services/callables/rules | no mobile-only role or direct mutation bypass | existing services | unchanged services | `PASS` |
| B10 | Payment push route | AppDelegate/SceneDelegate payment notification | preserve queued authenticated order route and real payment detail workflow | `AdminRouter` + route factory | source seam; push runtime pending | `UNVERIFIED` |
| B11 | Language | `Language` and notification rebuild | Arabic RTL/English LTR live switch through one singleton | SwiftUI environment derives from `Language` | static/localization checks; runtime pending | `UNVERIFIED` |
| B12 | Domain routes | dashboard route mapping | reuse existing production controllers, no duplicate details | `PPAdminRouteFactory` | repository-wide caller search | `PASS` |
| B13 | Command data | AppManager/payment/fulfillment/delivery/provider services | real aggregate data, permission-aware partial failures, refresh | `CommandCenterService` | service callback/static checks; runtime pending | `UNVERIFIED` |
| B14 | Accessibility | existing localized labels/Dynamic Type intent | native controls, 44pt actions, readable states, Reduce Motion path | SwiftUI views | physical assistive-tech run pending | `UNVERIFIED` |

No API, collection, field, callable, role, permission, persistence key, analytics event, or asset is added by inference.

## Phase 4 - Ownership Migration Ledgers

### Symbol Ledger

| Symbol/responsibility | Current owner | New owner | Compatibility requirement | Status |
|---|---|---|---|---|
| App root auth state | `SceneDelegate` | `AdminSessionStore` | one root-affecting session owner while AppDelegate retains push-token auth observation | `SOURCE COMPLETE / RUNTIME UNVERIFIED` |
| Login UI | `PPProLoginHostingController` | `AdminLoginView` | retain `PPProLoginCoordinator` callbacks | `SOURCE COMPLETE / RUNTIME UNVERIFIED` |
| Authenticated shell | SceneDelegate tab builder | `AdminAppShell` | retain route access and domain controllers | `SOURCE COMPLETE / RUNTIME UNVERIFIED` |
| Home/Dashboard | `AdminDashboardViewController` | `CommandCenterView` | preserve IAM exposure and valid destinations | `SOURCE COMPLETE / RUNTIME UNVERIFIED` |
| Route construction | dashboard method + SceneDelegate | `PPAdminRouteFactory` + `AdminRouter` | preserve special initializers and payment route | `SOURCE COMPLETE / RUNTIME UNVERIFIED` |
| Command aggregation | dashboard count listener | `PPAdminCommandCenterService` | use existing service owners and partial failures | `SOURCE COMPLETE / RUNTIME UNVERIFIED` |

### Call-Site Ledger

| Caller | Current target | Migration action | Verification | Status |
|---|---|---|---|---|
| `AppDelegate` iOS 12 fallback | pro login host | no migration change: app deployment target is iOS 15 | deployment/source inspection | `NOT APPLICABLE` |
| `SceneDelegate` launch/auth change | splash/login/dashboard roots | install one app-root host behind DEBUG and forward language/payment routes | source search | `SOURCE COMPLETE / RUNTIME UNVERIFIED` |
| Login completion notification | SceneDelegate root swap | session store restores authorized session | source search | `SOURCE COMPLETE / RUNTIME UNVERIFIED` |
| Payment push notification | SceneDelegate nav stack | forward order ID to `AdminRouter` | route parity/source search | `SOURCE COMPLETE / RUNTIME UNVERIFIED` |
| Command/module actions | dashboard route method | route factory full-screen navigation host | 33-identifier parity check | `SOURCE COMPLETE / RUNTIME UNVERIFIED` |

Rollback seam: restore the prior `SceneDelegate`/`AppDelegate` root constructors while new Swift/route-factory files remain isolated. No backend rollback is required.

## Phase 5 - Product DNA Card

| Dimension | Evidence-backed direction |
|---|---|
| Purpose | Authorized staff operate users, commerce, fulfillment, providers, payments, and platform controls. |
| Primary outcome | Reach the most important authorized operational task quickly and safely. |
| Dominant action | Resolve the highest-priority attention item or enter an active operation. |
| Audience/context | Repeated expert staff use; high information density; bilingual Arabic/English. |
| Emotional tone | Calm operational confidence with explicit risk and partial-failure states. |
| Brand truth | Qatar-maroon semantic palette, Beiruti typography, system symbols, continuous shapes, restrained material. |
| Existing behavior | Firebase session, `UsersCol` staff IAM, tabbed authenticated workspace, UIKit detail routes. |
| Native expectations | SwiftUI state rendering, TabView, native text fields/buttons/menus, UIKit bridges for existing workflows. |
| Information density | Many modules, but Command Center must prioritize health, attention, live operations, and business snapshot. |
| Signature opportunity | A permission-aware operational pulse that turns service state into a single calm attention queue. |
| Localization | Arabic primary RTL and English LTR via existing `Language`; mixed identifiers remain unmodified. |
| Accessibility | Dynamic Type, VoiceOver, Voice Control, Switch Control, keyboard, Reduce Motion/Transparency. |
| Technical constraints | iOS 15, Swift 6, Objective-C services, App Check, Firebase callbacks, no `xcodebuild` in this repo. |

## Phase 6 - V3 Creative Scorecard and Three Concepts

The V3 scorecard uses 0-5 across these 16 dimensions, in order: user/task fit, brand DNA, information architecture, operational clarity, native iOS behavior, Arabic RTL/English LTR, accessibility, state completeness, motion/Reduce Motion, performance/refresh, security/IAM, backend truth, migration safety, responsive adaptation, localization/content, and long-term leverage.

| Concept | Structural direction | Scores in the dimension order above | Total |
|---|---|---|---|
| A. Operational Pulse | Health header, prioritized needs-attention queue, live operations, business snapshot, contextual actions; five-tab shell | 5,5,5,5,4,5,5,5,4,4,5,5,5,5,5,5 | 77/80 |
| B. Queue First | Attention inbox dominates; metrics and routes become secondary inspector regions | 5,4,4,5,4,4,4,5,4,4,5,4,4,4,4,4 | 68/80 |
| C. Module Constellation | Adaptive module board with live badges and drill-down panes | 3,3,3,4,4,4,3,3,3,3,4,3,2,4,4,3 | 50/80 |

Chosen: **A. Operational Pulse**. It is the only concept that simultaneously makes operational health, real attention work, and permission-aware routes primary without recreating the old module directory. B was rejected because the backend does not expose one universal queue authority and the inspector pattern would hide live operational context. C was rejected because it repeats the directory-first hierarchy and increases migration risk. The implementation uses a restrained solid brand surface, semantic status tint, native controls, no custom animation, and no arbitrary glass treatment.

## Phase 7 - Implementation

Status: `SOURCE COMPLETE / NATIVE RUNTIME UNVERIFIED`.

The implementation owner is `swiftymax-studio-v3`; certification remains reserved for `swiftymax-proof-v3`.

Implemented source:

- `AdminSessionStore` is the single SwiftUI root session owner for restoring, unauthenticated, authenticated, unauthorized, disabled, retry, foreground revalidation, and sign-out states.
- `PPAdminSessionBridge` reuses Firebase Auth, `PPStaffAuth.refreshCurrentStaff`, `FUManager`, `UserManager`, the existing user cache, canonical role/permission mapping, and the existing notification-safe logout barrier. A live `PPStaffAuth.listenStaffDoc` observation now projects permission, role, status, and scope changes into `AdminSessionStore`; revocation or disablement immediately removes the authenticated shell and signs out.
- `AdminAuthenticationService` and `AuthenticationState` adapt the existing `PPProLoginCoordinator`; email, Google, biometric, remember-me, password reset, App Check errors, and staff gating are not reimplemented.
- `AdminLoginView` provides adaptive compact/regular Login layouts, secure-field reveal, native focus/submit behavior, loading/alert states, language switching, Dynamic Type fonts, and 44-point controls.
- `AdminAppShell` owns the five requested tabs: Command, Work, Operations, Customers, and More. Destinations are filtered through canonical staff permissions; personal account and settings remain available without introducing a new privilege.
- `CommandCenterView` implements Operational State, Needs Attention, Live Operations, Business Snapshot, contextual actions, first-load, refresh, empty, full-failure, clear, partial-failure, and permission-filtered states. Attention items carry stable IDs, domain, severity, timestamp, optional entity ID, and required permissions, then sort by severity, count, and ID. Orders are explicitly labeled as the latest 100 because the existing payment service is page-limited; no false global total is claimed.
- `PPAdminCommandCenterService` aggregates the existing payment, fulfillment, delivery, provider, `pet_ads`, `UsersCol`, and `petAccessories` authorities. Payment terminal helpers come from the existing model; fulfillment attention mirrors Infra's pending-provider set; delivery mirrors Infra's official-company authorization and active lifecycle and paginates all callable pages.
- The listings route carries an explicit all-of guard for both the catalog's `listings.*` permission and Infra's current direct-read requirement, `stock.manage`; the Command Center does not request a `pet_ads` count for staff who cannot satisfy both.
- `AdminRouter` and `PPAdminRouteFactory` expose all 33 typed identifiers, including the payment push payload and all currently reachable legacy dashboard destinations. Existing UIKit controllers and required special initializers are reused.
- `AdminAppRootHostingController` is installed only behind a DEBUG `SceneDelegate` seam. Language and payment notification forwarding are connected. Release behavior still uses the verified legacy root until native proof closes.
- The project deployment target remains the repository contract of iOS 15.0. The migration restores that target after the intake diff had raised it to 18.6, and keeps the SwiftUI implementation on iOS 15-compatible APIs.
- Canonical `staff_users` role-only records now receive the same role defaults as Infra’s `resolvedStaffPermissions`; missing/empty permission arrays do not create a client-only denial.
- Session revocation and disabled records produce separate localized outcomes, protected routes are cleared when the root becomes unauthenticated, and foreground revalidation preserves the authenticated shell while it checks authorization.
- Objective-C `PPAdminSessionBridgeErrorCode` comparisons use the Swift-imported typed enum cases (`.unauthorized` and `.disabled`) rather than unavailable unscoped C identifiers.
- Foreground session revalidation snapshots only Firebase Auth's UID `String` before crossing the bridge callback; the non-Sendable Firebase `User` object is not captured by a `@Sendable` main-actor task.
- Sign-out uses the bridge's async throwing overload. Unauthorized-session cleanup still transitions to unauthenticated after the sign-out attempt, while user-initiated sign-out still resumes staff observation if the sign-out fails.
- `PurePetsAdminTests.m` now covers role-only default permissions, disabled staff denial, and unknown-role viewer fallback with explicit permissions retained.
- Arabic and English copy for the migration keys is paired. SwiftUI layout direction derives from the existing `Language` singleton; identifiers and email text remain unmodified.
- No custom animation was added, so Reduce Motion cannot be bypassed by this migration source.

State matrix:

| Surface | States implemented in source | Native evidence |
|---|---|---|
| App root | restoring, restore failure/retry, unauthenticated, authenticated, unauthorized/sign-out | `UNVERIFIED` |
| Login | idle, email loading, Google loading, biometric loading, password reset, failure alert, language switch | `UNVERIFIED` |
| Command Center | loading, loaded, refreshing, clear attention, active attention, partial data, permission-filtered metrics/actions | `UNVERIFIED` |
| Routing | allowed, permission denied, unavailable factory fallback, payment push queued before session, UIKit dismiss | `UNVERIFIED` |
| Session end | confirmation, signing out, failure retained, successful unauthenticated transition | `UNVERIFIED` |

Changed implementation files:

- `PurePetsAdmin/App/AdminAppRoot.swift`
- `PurePetsAdmin/App/AdminAppShell.swift`
- `PurePetsAdmin/App/AdminTab.swift`
- `PurePetsAdmin/Features/Authentication/AuthenticationState.swift`
- `PurePetsAdmin/Features/Authentication/AdminLoginView.swift`
- `PurePetsAdmin/Features/CommandCenter/CommandCenterModels.swift`
- `PurePetsAdmin/Features/CommandCenter/CommandCenterState.swift`
- `PurePetsAdmin/Features/CommandCenter/CommandCenterView.swift`
- `PurePetsAdmin/Services/Session/PPAdminSessionBridge.h/.m`
- `PurePetsAdmin/Services/CommandCenter/PPAdminCommandCenterService.h/.m`
- `PurePetsAdmin/Delivery/PPDeliveryService.h/.m`
- `PurePetsAdmin/UsersSection/SecFil/PPStaffAuth.h/.m`
- `PurePetsAdmin/UsersSection/UserController/PPProLoginCoordinator.m`
- `PurePetsAdmin/AppManager.m`
- `PurePetsAdmin/Shared/Routing/AdminRoute.swift`
- `PurePetsAdmin/Shared/Routing/PPAdminRouteFactory.h/.m`
- `PurePetsAdmin/SceneDelegate.h/.m`
- `PurePetsAdmin/PurePetsAdmin-Bridging-Header.h`
- `PurePetsAdmin/en.lproj/Localizable.strings`
- `PurePetsAdmin/ar.lproj/Localizable.strings`
- `PurePetsAdminTests/PurePetsAdminTests.m`
- `PurePetsAdmin.xcodeproj/project.pbxproj`

## Phase 8 - Validation and Proof

Status: `BLOCKED / UNVERIFIED` for native proof.

Static validation completed without `xcodebuild`:

| Gate | Result |
|---|---|
| New Swift source parse via `xcrun swiftc -frontend -parse` | `PASS` |
| Objective-C `NS_ENUM` to Swift importer probe for session error cases | `PASS` - typed `.unauthorized` and `.disabled` cases resolve; unscoped identifiers reproduce the reported failure |
| Swift 6 strict-concurrency session bridge probe | `PASS` - UID-only restore capture and async sign-out paths type-check with warnings treated as errors |
| Xcode project syntax via `plutil -lint` | `PASS` |
| English/Arabic strings syntax via `plutil -lint` | `PASS` |
| Command Center localization parity | `PASS` - 80 keys in both Arabic and English |
| Literal migration localization references | `PASS` - 64 literal references resolved; generated `CommandCenter_Area_\\(area)` key intentionally excluded |
| Project file references | `PASS` - 15/15 paths exist |
| App target source membership | `PASS` - 12/12 source entries |
| Canonical staff IAM model test coverage | `SOURCE ADDED / UNVERIFIED` - three focused XCTest cases; test execution is blocked by the no-`xcodebuild` repository rule |
| Swift route/UIKit route factory parity | `PASS` - 33 identifiers |
| Local Objective-C import paths | `PASS` |
| Migration PBX object definitions | `PASS` - 27 unique; three unrelated duplicate IDs pre-exist in the project |
| Patch whitespace via `git diff --check` | `PASS` |

Blocked native gates:

- Swift/Objective-C importer type-check and app compile.
- Physical-device launch, restoring session, email/Google/biometric Login, IAM-negative fixtures, logout barrier, payment push route, and every reused UIKit destination.
- Arabic RTL, English LTR, iPhone/iPad adaptation, Dynamic Type, VoiceOver, Voice Control, Switch Control, hardware keyboard, Reduce Motion, Reduce Transparency, and contrast evidence.
- Instruments/signpost performance, memory, network, and command refresh evidence.
- Release-root switch, legacy Login/Dashboard deletion, and temporary migration seam deletion.

Reason: repository policy explicitly forbids `xcodebuild`, simulator evidence is forbidden, and no alternative repository-authorized physical-device compile/install workflow is present. The connected iPhone alone cannot establish build or runtime proof.

Independent proof status: source review and static gates cover the session/IAM seam, Infra permission alignment, locale key parity for the migration, route ledger, logout route reset, stale-request guard, and explicit Command Center state matrix. Native proof remains unavailable and no certification object exists.

## Certification

`BLOCKED / UNVERIFIED`

No score is displayed. The exact SwiftyMax Proof V3 certification object has not passed.
