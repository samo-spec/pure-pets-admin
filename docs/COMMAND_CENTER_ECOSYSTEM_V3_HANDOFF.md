# Command Center Ecosystem V3 Handoff

## Scope And Identity

- Original request: continue from the existing Command Center in the Admin app, discover every connected operational route, and make every child workflow feel like a deliberate extension of the same Command Center without removing real functionality.
- Target: `Pure Pets Admin`, iOS/iPadOS staff application.
- Baseline commit: `60fea8c0b3796198bf42df47f0de92f53aebd31e`.
- Worktree: already modified at intake by prior work; those changes remain untouched and are not attributed to this pass. This pass adds a bounded Command Center ecosystem layer.
- Deployment contract: iOS 15.0 minimum, UIKit/Objective-C domain screens with SwiftUI root and shell already present in the target.
- Mode: `redesign` with one reversible ownership seam.
- Scope: `AdminAppShell`, `CommandCenterView`, shared Command Center state, typed route metadata, `AdminLegacyRouteView` presentation chrome, release root selection, and paired Admin localization.
- Included route branch: all 33 `AdminRoute` identifiers, including payment deep links and nested UIKit workflows constructed by `PPAdminRouteFactory`.
- Exclusions: Firebase schema, Firestore rules, Cloud Functions, service request shapes, permissions, analytics identifiers, domain controller business logic, unrelated existing worktree changes, and production deployment.
- Authorities: `Pure Pets Infra/`, `PPStaffAuth`, `RPManager`, `FUManager`, `UserManager`, `AppManager`, existing payment/fulfillment/delivery/provider services, `PPAdminRouteFactory`, `Language`, and the current Admin Command Center handoff.
- Restrictions: no `xcodebuild`; no simulator evidence; physical-device evidence only; Xcode default DerivedData only; do not start tests when trusted free space is at or below 20%.
- Connected device observed: `iPhone (26.5.2)`; iPhone 13 Pro Max was not available. iPad and iPhone 12 Pro Max were offline.
- Current external blocker: the host reports 3.9 GiB available and 99% capacity, so new build/test/profiling work is blocked under the repository rule.

## Acceptance Criteria

1. The normal root enters the existing `AdminAppRootHostingController`, so the Command Center is not DEBUG-only.
2. One `CommandCenterState` instance owns the operational snapshot for the authenticated shell.
3. Command Center, Work, Operations, Customers, and More retain their existing routes and permission filtering while sharing the same operational pulse.
4. Every typed route keeps its existing factory identifier, payload, controller, service, nested navigation, and dismissal behavior.
5. Every route reached from the Command Center carries the localized Command Center context in its native navigation chrome.
6. Arabic remains RTL, English remains LTR, user-facing additions are localized in both tables, and identifiers remain copy-safe.
7. No backend write, collection, permission, analytics event, persistence key, or domain action is invented or changed.

## Preserved Behavior Ledger

| ID | Source evidence | Preserved contract | Target owner | Status |
|---|---|---|---|---|
| B01 | `SceneDelegate.m`, `AdminAppRoot.swift` | Splash/auth/session state remains the root gate; normal builds use the SwiftUI root, with `PP_ADMIN_LEGACY_ROOT` as an explicit rollback seam. | `AdminSessionStore` + `AdminAppRoot` | UNVERIFIED runtime |
| B02 | `PPProLoginCoordinator.m`, `AuthenticationState.swift` | Email, Google, biometric, remember-me, reset, App Check, and staff-gate behavior remain delegated to the existing coordinator bridge. | `AdminAuthenticationService` | PASS source |
| B03 | `AppDelegate.m`, `SceneDelegate.m`, `AdminRouter` | `payments_order` payloads still queue until an authorized authenticated root can consume the order ID. | `AdminRouter` + existing payment service | UNVERIFIED runtime |
| B04 | `PPStaffAuth.m`, `AdminRoute.swift` | Canonical staff status, role, scope, and permission checks still gate all typed routes; the listings all-of guard remains. | `PPStaffAuth` + `AdminRouter` | PASS source |
| B05 | `PPAdminCommandCenterService.m` | Snapshot data still comes from existing payment, fulfillment, delivery, provider, `pet_ads`, `UsersCol`, and `petAccessories` authorities. | `PPAdminCommandCenterService` | PASS source |
| B06 | `PPPaymentManagementService`, `PPFulfillmentService`, `PPDeliveryService`, `PPProviderService` | Child route controllers remain the owners of reads, writes, callable actions, validation, audit side effects, pagination, and recovery. | Existing UIKit/Swift controllers | PASS source |
| B07 | `AdminRoute.swift`, `PPAdminRouteFactory.m` | Route identifiers, payloads, controller initializers, nested pushes, and close dismissal remain unchanged. | `PPAdminRouteFactory` + route container | UNVERIFIED runtime |
| B08 | `AdminSessionStore`, `CommandCenterState` | One session owner and one Command Center aggregate owner remain active; shell tabs observe the same state instance. | `AdminSessionStore` + shell-owned `CommandCenterState` | PASS source |
| B09 | `CommandCenterState.swift`, `CommandCenterView.swift` | Loading, retained refresh, empty, partial, full failure, retry, stale-request cancellation, and permission-filtered metrics remain reachable. | `CommandCenterState` | UNVERIFIED runtime |
| B10 | `Language.m`, paired `Localizable.strings`, SwiftUI environment setup | Arabic/English switching, layout direction, localized route labels, and locale-aware displayed counts/times remain owned by the existing language system. | `Language` + SwiftUI environment | UNVERIFIED runtime |
| B11 | `AdminConnectedRouteChrome`, UIKit route controllers | UIKit child workflows keep their own navigation, focus, keyboard, scroll, delegate, callback, and action ownership; the new layer only applies presentation chrome. | Route container chrome | PASS source |
| B12 | `PPAdminCommandCenterService.h`, `CommandCenterState.swift` | Snapshot refresh uses request IDs and does not apply stale results after cancellation or session change. | `CommandCenterState` | PASS source |

No changed-contract approval was requested or granted. No Symbol Ledger or Call-Site Ledger requires a public contract migration in this pass; the only ownership change is hoisting the existing Command Center state to the authenticated shell so sibling tabs can observe it.

## Product DNA Card

| Dimension | Evidence-backed decision |
|---|---|
| Product purpose | Give authorized staff one calm operational entry point for commerce, fulfillment, delivery, providers, users, and platform controls. Evidence: `README.md` features and `PPAdminCommandCenterService.m`. |
| Primary outcome | Reach the highest-priority authorized operational task without losing platform context. Evidence: existing attention items and typed route factory. |
| Dominant action | Resolve an attention item or enter a live operational lane. Evidence: `CommandCenterState.map(_:)` and the existing Command Center sections. |
| Audience and context | Repeated expert staff use across compact iPhone and regular iPad widths. User frequency and expertise are inferred only from the internal staff product contract; exact staffing research is unknown. |
| Emotional tone | Calm, explicit, accountable, and non-theatrical. This follows the operational risk of payment/fulfillment actions and the existing semantic status palette. |
| Brand truth | Beiruti typography, Pure Pets semantic colors, system symbols, logical anchors, paired Arabic/English localization, and existing UIKit design tokens. Evidence: `PPDesignTokens.h/.m`, `Language`, and current Admin screens. |
| Existing behavior | Firebase Auth/App Check/staff IAM, one authenticated shell, typed route factory, existing service listeners/callables, and UIKit workflow stacks. |
| Native expectations | Native `TabView`, `Button`, `ScrollView`, `refreshable`, UIKit navigation stacks, native dismissal, VoiceOver semantics, and Dynamic Type. Deployment is iOS 15. |
| Information density | High and variable. The actual Command Center can expose only permission-aware counts and the latest payment page; it must not imply global totals where the service is page-limited. |
| Signature opportunity | A shared operational pulse that travels with staff from Command Center into every workflow, rather than a decorative dashboard header. |
| Localization | Arabic primary RTL and English secondary LTR through the existing `Language` singleton; email, order IDs, and route identifiers remain LTR/copy-safe. |
| Accessibility | Native controls, combined status rows, 44-point refresh/action targets, Dynamic Type fonts, semantic symbols, non-gesture paths, Reduce Motion compatibility, and runtime VoiceOver/AX5 verification required. |
| Technical constraints | Existing Objective-C services and UIKit controllers remain authoritative; no backend changes; App Check and IAM stay intact; no simulator or `xcodebuild` evidence is permitted. |

## Three Structural Concepts And Scores

Scores use the V3 16 dimensions in order: task clarity, Product DNA fit, information architecture, visual hierarchy, typography craft, color/material/iconography, native Apple behavior, interaction delight, accessibility/RTL resilience, reachable states, motion meaning, animation craft, performance feasibility, migration safety, anti-genericity, and long-term product leverage.

### A. Operational Spine, selected

- Structure: a single operational signal leads into an attention queue; live and business lanes follow; every secondary tab begins with the same pulse strip; every UIKit destination carries a visible Command Center context bar above its native navigation stack.
- Composition: attention is the dominant region; metric data is a readable vertical ledger rather than a generic card grid; contextual actions close the loop.
- Interaction: tap an attention row or lane row to use the existing route; tap the pulse strip to return to Command Center; refresh remains native and immediate.
- Signature: the operational pulse persists across tab changes and route presentation, using the existing snapshot only. Non-gesture fallback is provided by ordinary buttons and tab selection.
- States: existing loading, retained, empty, partial, failed, retry, permission-filtered, route-denied, and unavailable states remain represented.
- Adaptation: compact widths stack queue and lanes; regular widths split the attention queue from live/business lanes without changing order or action ownership.
- Transplant test: copied into a generic CRM, this concept would fail because its hierarchy is tied to Pure Pets fulfillment/payment/provider queues and canonical staff permissions.
- Scores: `5, 5, 5, 5, 4, 4, 5, 4, 5, 5, 4, 4, 4, 5, 5, 5` = `74/80`.

### B. Queue First

- Structure: a single full-screen attention inbox dominates; metrics become a secondary inspector and route selection is mostly queue-driven.
- Composition: unresolved work occupies the first and largest viewport; live/business context is disclosed after selection.
- Interaction: swipe/selection would triage queue items, with a button fallback and a detail inspector.
- Signature: useful only if one universal backend queue authority exists. The current sources expose separate payment, fulfillment, delivery, and provider authorities, so the design would falsely imply a unified queue.
- Adaptation: compact is viable, but regular width would require a split inspector and more state synchronization.
- Transplant test: copied into a product with a single canonical incident queue it would work, proving it is not specific enough to Pure Pets.
- Rejection: it hides cross-domain live context and would require inventing queue semantics not present in `PPAdminCommandCenterService`.
- Scores: `5, 4, 5, 5, 4, 4, 5, 5, 4, 5, 4, 4, 4, 4, 4, 4` = `70/80`.

### C. Module Constellation

- Structure: a directory-first constellation of permission-aware module nodes with live badges and drill-down panes.
- Composition: module navigation dominates; operational health is distributed across nodes instead of being a single signal.
- Interaction: direct module selection and badge expansion with ordinary button fallback.
- Signature: visually distinctive but repeats the old directory behavior already owned by `AdminDashboardViewController` and adds no evidence-backed operational advantage.
- Adaptation: regular width favors a board; compact width collapses into the same old list.
- Transplant test: copied into any enterprise admin product, the board would look nearly identical because its structure is not tied to Pure Pets workflow semantics.
- Rejection: it risks reintroducing the legacy dashboard hierarchy and has the highest migration and accessibility risk.
- Scores: `4, 4, 3, 4, 4, 4, 4, 3, 3, 3, 4, 3, 3, 2, 3, 4` = `55/80`.

Concept A is selected because it is the only eligible direction above 72/80 while preserving the existing service and route owners. The other two are rejected for concrete information-architecture and contract reasons, not palette preference.

## Chosen Direction

- North star: `مركز القيادة` is a persistent operational context, not a dashboard destination.
- Visual hierarchy: operational signal → needs attention → live operations/business lanes → contextual actions → last update.
- Typography: existing Beiruti semantic roles with Dynamic Type scaling; counts use monospaced digits; identifiers remain isolated by their existing LTR treatment.
- Material and color: existing semantic surfaces and status colors; no new gradients, blur, ambient loops, or arbitrary glass were added in this pass.
- Iconography: existing SF Symbols tied to domain semantics; decorative symbols remain hidden from assistive technology.
- Primary interactions: refresh, attention route, metric route, contextual route, pulse return, native full-screen workflow close, and existing child actions.
- Motion: no new custom motion owner. Existing native refresh/presentation transitions remain; Reduce Motion must preserve all state and action meaning.
- Anti-goals: generic dashboard grid, decorative gradient, excessive pills, gesture-only triage, duplicate route stores, duplicate listeners, and invented “global” totals.

## Changed Files In This Pass

- `PurePetsAdmin/App/AdminAppShell.swift`: hoists one Command Center state owner, adds a shared pulse strip to every shell lane, and keeps route filtering/dismissal intact.
- `PurePetsAdmin/Features/CommandCenter/CommandCenterState.swift`: exposes the latest usable snapshot to sibling surfaces without creating another listener or aggregate.
- `PurePetsAdmin/Features/CommandCenter/CommandCenterView.swift`: replaces the generic metric grid with signal, attention ledger, operational lanes, contextual actions, and adaptive compact/regular composition.
- `PurePetsAdmin/Shared/Routing/AdminRoute.swift`: adds route lane metadata and a visible Command Center context bar to every typed workflow stack.
- `PurePetsAdmin/SceneDelegate.m`: makes the SwiftUI root the normal root; legacy root remains available only through explicit `PP_ADMIN_LEGACY_ROOT` rollback compilation.
- `PurePetsAdmin/en.lproj/Localizable.strings`: English copy for signal, empty lanes, action absence, and workflow dismissal.
- `PurePetsAdmin/ar.lproj/Localizable.strings`: Arabic copy paired with the English additions.
- `docs/COMMAND_CENTER_ECOSYSTEM_V3_HANDOFF.md`: this evidence-bounded handoff.

Pre-existing modified files in the Admin worktree were preserved and are not reclassified as part of this pass.

## State Matrix

| Surface | Reachable source states | Runtime evidence |
|---|---|---|
| Root/session | restoring, unauthenticated, authenticated, denied, disabled, retry, sign-out | UNVERIFIED |
| Command Center | idle/loading, loaded, retained refresh, empty, partial failure, full failure, retry, stale cancellation | UNVERIFIED |
| Shared pulse | loading, stable, attention, partial, return-to-command action | UNVERIFIED |
| Shell lanes | permission-filtered routes, empty route lane, pulse loading/loaded/partial | UNVERIFIED |
| Typed workflows | authorized, denied, unavailable factory fallback, native nested navigation, native close | UNVERIFIED |
| Payment deep link | queued before auth, consumed after auth, load failure, payment detail stack | UNVERIFIED |
| Language | Arabic RTL, English LTR, live switch, mixed email/order identifiers | UNVERIFIED |
| Lifecycle | foreground revalidation, cancellation on state change, logout route reset | UNVERIFIED |

## Accessibility And RTL Matrix

- Source checks: native `Button`, `Toggle`, `TextField`, `SecureField`, `refreshable`, combined status rows, 44-point refresh/control frames, hidden decorative symbols, logical SwiftUI alignment, and UIKit semantic direction are present.
- Required runtime checks: VoiceOver labels/hints/focus, Voice Control names, Switch Control order, Full Keyboard Access, AX5 reflow, increased contrast, Reduce Transparency, Reduce Motion, Arabic RTL route order, English LTR route order, mixed-script identifiers, and live language restoration.
- Status: `UNVERIFIED`; no simulator substitution is allowed and no physical-device run was started after the disk guard.

## First-Render Critique

- Representative source artifacts: `CommandCenterView.swift`, `AdminAppShell.swift`, and `AdminRoute.swift` current worktree versions. Native screenshots/contact sheets are not available because the required build/runtime gate is blocked.
- Iteration count: `2` source passes, with one bounded correction to add the visible route context bar; no autonomous redesign loop was started.
- Product specificity: PASS at source level; the hierarchy is tied to existing payment/fulfillment/delivery/provider authorities.
- Hierarchy at a glance: PASS at source level; the signal and attention ledger precede lanes.
- Composition rhythm: PASS at source level; compact stacks and regular split are explicit.
- Typographic expression: PASS at source level; Beiruti roles and monospaced counts are retained.
- Color/material restraint: PASS at source level; semantic surfaces/status tones only in this pass.
- Iconographic coherence: PASS at source level; existing SF Symbols map to route/domain semantics.
- Interaction clarity: PASS at source level; every action has a native button path and existing route owner.
- Motion choreography: UNVERIFIED; native device capture, interruption, and Reduce Motion evidence are unavailable.
- RTL/accessibility adaptation: UNVERIFIED; source intent is present but physical assistive-tech/runtime evidence did not run.
- State/recovery craft: PASS at source level; existing state enum and retry/partial/failure paths remain in the owner.
- First-pass readiness: `false` for independent native proof, because the current render artifact is source-bound rather than device-bound.

## Motion Phase Model

- Trigger: user refresh, tab selection, route presentation, or existing service state transition.
- Owner: `CommandCenterState` owns refresh state; SwiftUI/UIKit system presentation owns route transitions; domain controllers retain their existing action motion.
- Phase order: preserve content → show processing indicator → apply current snapshot → expose updated signal/queue/lanes.
- Interaction: refresh and dominant route actions remain available; no gesture-only action was introduced.
- Cancellation: `CommandCenterState` invalidates the request ID; route dismissal remains owned by the existing container/coordinator.
- Reduce Motion: static state change and processing indicator still expose the same meaning; no new perpetual animation was introduced.
- Haptics/audio: none added.
- Measurement: physical-device frame pacing and interruption capture required; currently `BLOCKED/UNVERIFIED`.

## Validation And Evidence

| Command/gate | Result |
|---|---|
| `xcrun swiftc -frontend -parse` on changed Swift files | BLOCKED/UNVERIFIED: an earlier parse pass was invalidated by the bounded `AdminRoute.swift` context-bar correction; no rerun is permitted while free space is below 20% |
| `plutil -lint` on English/Arabic strings and Xcode project | PASS |
| `git diff --check` | BLOCKED/UNVERIFIED: an earlier pass was invalidated by the bounded source correction; no rerun is permitted while free space is below 20% |
| Route call-site search | PASS source; 33 typed identifiers remain |
| Physical-device compile/install/launch | BLOCKED/UNVERIFIED: repository forbids `xcodebuild`; free space is below 20% |
| Simulator evidence | NOT APPLICABLE/FORBIDDEN by target policy |
| VoiceOver/RTL/AX5/Reduce Motion | BLOCKED/UNVERIFIED |
| Instruments/performance | BLOCKED/UNVERIFIED |
| Independent proof package and current hashes | BLOCKED/UNVERIFIED |

Do not start additional tests while the trusted host reports 3.9 GiB free and 99% capacity. The exact next action is to free space above the 20% threshold, then use the connected physical iPhone (or the requested iPhone 13 Pro Max when available) with the repository-authorized non-simulator device workflow. No source change is required before that gate.

## Certification

The exact Proof V3 result object is not available for this target. Because native build/runtime/accessibility/performance evidence is blocked and the current worktree contains pre-existing unrelated modifications, the only honest terminal state is:

`BLOCKED/UNVERIFIED`
