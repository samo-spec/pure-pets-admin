# Admin Command Center Priority Handoff V6

## Verdict

`BLOCKED/UNVERIFIED`

The source implementation and static review are complete. Current-byte native visual, motion, accessibility, RTL, and performance proof is blocked because the host has 5.6 GiB free at 98% capacity, below the repository's recorded 20% build/test safety gate. The connected physical device is an iPhone 13 Pro Max, but no build, install, launch, or capture was attempted under that storage condition.

## Frozen Target

- Request: redesign and animate the Pure Pets Admin main command center.
- Mode: `redesign` plus an explicit `animate` deliverable.
- Platform: native iOS/iPadOS Admin app, iOS 15.0 minimum.
- Active route: `AdminAppRoot` -> `AdminAppShell` -> Command tab -> `AdminCommandOrbitContainerController` -> `AdminDashboardViewController` -> `AdminCommandOrbitHostingController`.
- Presentation owner: `Features/CommandCenter/CommandOrbitDirect.swift`.
- Data, priority, permission, and concrete route owner: `AdminDashboardViewController.m` plus existing services.
- Navigation owner: UIKit navigation in `AdminCommandOrbitContainerController` and `AdminDashboardViewController`.
- Brand authority: `PPDesignTokens.h/.m`, `AdminSurface`, `AdminType`, Beiruti, paired localization, and repository-owned `AD_LOGO`; no logo was needed or reconstructed.
- Exclusions: Firebase schema, Cloud Functions, service request/response shapes, destructive workflow actions, destination controller redesign, analytics, persistence, deployment, and unrelated dirty-worktree files.

## Acceptance Contract

1. Keep the Objective-C descriptor fields, `applyRoleName:capabilityCount:signals:animated:`, `onRoute`, six-item cap, stable tags, and one UIKit route callback.
2. Keep Firebase and business priority computation outside SwiftUI.
3. Present the highest-ranked authorized signal with full module, title, detail, count, and priority context; keep remaining signals directly actionable.
4. Use compact vertical, regular asymmetric, and AX1-AX5 linear reflow without truncating task copy.
5. Preserve Arabic RTL and English LTR, locale-aware digits, dark mode, increased contrast, Reduce Transparency, Reduce Motion, VoiceOver, Switch Control, and low-power behavior.
6. Remove decorative/perpetual radar motion, duplicate route haptics, and route delay.
7. Animate only changed descriptor content with bounded, interruptible, opacity-only feedback.

## Behavior Ledger

| ID | Contract | Authority | Result |
|---|---|---|---|
| B01 | Command remains the first authenticated tab. | `AdminAppShell.swift` | PASS source |
| B02 | Objective-C remains permission, listener, priority, and destination owner. | `AdminDashboardViewController.m` | PASS source |
| B03 | Swift bridge keeps all public descriptor fields, six-item cap, deduplication, and order. | `CommandOrbitDirect.swift` | PASS source |
| B04 | Tapping a signal emits its unchanged tag once, immediately, without a Swift haptic or delay. | Swift `route(_:)`; ObjC `pp_handleDashboardActionForTag:` | PASS source; runtime UNVERIFIED |
| B05 | UIKit remains the only navigation-transition owner. | `AdminAppShell.swift`; dashboard route handler | PASS source; runtime UNVERIFIED |
| B06 | Arabic/English direction and structural copy refresh without recreating navigation; ObjC rebuilds localized descriptors. | `LanguageDidChangeNotification`; paired strings | PASS source; runtime UNVERIFIED |
| B07 | Canonical `PPStaffDoc` permissions gate dashboard modules; legacy role value 5 no longer grants a Payments Manager all modules. | `PPStaffAuth`; dashboard canonical alias bridge | PASS source; IAM runtime UNVERIFIED |
| B08 | Auth changes rebuild the visible command snapshot. | shell session update notification | PASS source; runtime UNVERIFIED |
| B09 | Payment Basics remains reachable through Work only for `payments.manage`. | `AdminAppShell.swift`; `AdminRoute.swift` | PASS source; runtime UNVERIFIED |
| B10 | Live and one-shot feeds stop publishing offscreen; stale generations are rejected. | dashboard visibility and generation guards | PASS source; runtime UNVERIFIED |
| B11 | Empty, one-signal, and up-to-six-signal states remain representable. | Swift presentation model | PASS source; fixtures UNVERIFIED |
| B12 | No backend, analytics, persistence, or destination action contract changed. | scoped diff | PASS source |

## Creative Direction

### Product DNA

- Purpose: help authorized staff reach the most consequential active Pure Pets operation without losing route context.
- Tone: calm, explicit, accountable, and non-theatrical.
- Dominant outcome: enter the highest-priority authorized payment, fulfillment, delivery, stock, or management task.
- Brand expression: Beiruti hierarchy, semantic Pure Pets surfaces/status roles, Arabic-first composition, and source-owned SF Symbols.
- Anti-goals: KPI grid, equal-weight card wall, decorative radar, ambient loops, generic glass, invented totals, and gesture-only actions.

### Concepts Reviewed

1. **Priority Handoff, selected:** one full-context dominant signal plus an urgency-ordered action ledger.
2. **Concentric Triage Map, rejected:** retained radial topology but weakened immediate task clarity and AX/RTL resilience.
3. **Severity Bands, rejected:** clear triage but failed the anti-genericity test.

Priority Handoff was the only concept with no source-level selection failure. Pixel-level typography, spacing, hierarchy, and material quality remain unverified because no current baseline or candidate render exists.

## Implementation

- `CommandOrbitDirect.swift`
  - Replaced the radar/sonar stage with Priority Handoff.
  - Added compact, regular, and AX accessibility layouts.
  - Exposes full signal context instead of hiding task title/detail in radial nodes.
  - Uses semantic status shape/color plus high-contrast text.
  - Refreshes language direction and locale without a second data owner.
  - Removed entrance staging, sonar, pulses, route delay, and duplicate Swift haptics.
  - Added one 120 ms `0.88 -> 1.0` opacity settle for changed stable IDs only.
- `AdminDashboardViewController.m`
  - Rebuilds localized descriptors on language changes.
  - Uses canonical `PPStaffDoc` authorization rather than legacy role escalation.
  - Refreshes authorization from the shell session.
  - Removes duplicate one-shot refreshes and rejects offscreen/stale feed results.
- `AdminAppShell.swift`
  - Propagates canonical session changes to the embedded dashboard.
  - Restores Payment Settings to the Work route list.
- `AdminRoute.swift`
  - Narrows Payment Settings to `payments.manage`.
  - Keeps UIKit chrome work on the main actor.
- `en.lproj/Localizable.strings`, `ar.lproj/Localizable.strings`
  - Adds paired labels for the primary and remaining priority regions.

## Motion Contract

- Decision: `reduce`.
- Trigger: a host-applied snapshot changes one or more stable descriptors while visible and active.
- Phase: one opacity-only settle after new content is committed.
- Timing hypothesis: 120 ms ease-out, matching `PPAnimDurationFast`.
- Interaction: all routes remain available; route callback is synchronous.
- Cancellation: newer snapshot, route activation, disappearance, background, Reduce Motion, Reduce Transparency, low power, VoiceOver, Switch Control, or AX Dynamic Type establishes the latest static state immediately.
- Continuous work: none.
- Reduce Motion equivalent: identical content, hierarchy, order, and actions at full opacity.
- Runtime interruption and frame pacing: UNVERIFIED.

## Static Evidence

- `xcrun swiftc -frontend -parse` on the three changed Swift seams: PASS.
- `plutil -lint` on English/Arabic strings and `project.pbxproj`: PASS.
- `git diff --check` on tracked changed seams: PASS.
- Independent compile/API review: no remaining task-scope Critical, High, or Medium findings.
- Independent behavior/accessibility/IAM review: no remaining task-scope Critical, High, or Medium findings.
- CodeRabbit: unavailable (`command not found`).
- Xcode build/test: BLOCKED by storage gate; not run.

## Current Source Hashes

| File | SHA-256 |
|---|---|
| `PurePetsAdmin/Features/CommandCenter/CommandOrbitDirect.swift` | `7daaed294ace8dad3f56f68f0961f02109ed608c65642ee02aa96c7d2226768f` |
| `PurePetsAdmin/AdminDashboardViewController.m` | `1ab80f45e9f6fd0dc6ea46648f412c0f2cae5732d5118b3760a8e249842db5a0` |
| `PurePetsAdmin/App/AdminAppShell.swift` | `9bf6911a45c29f67d67fb57eead0c6f114051e00cbe0594c92c3f2841a4cdf09` |
| `PurePetsAdmin/Shared/Routing/AdminRoute.swift` | `e380d2d49eddf121e91d2b6828ea1e1b1180dda2fe1cefc9672e47086391f8e2` |
| `PurePetsAdmin/en.lproj/Localizable.strings` | `750f30cdefa2cc8a9416815945fdc30754302ffe870322faf5256b09a4439728` |
| `PurePetsAdmin/ar.lproj/Localizable.strings` | `ee19c3fd5460f67c79c52c98d86f3e8af746d3a23c57997d29aaa5c41334734e` |

The hashes above predate this handoff file only. Any subsequent change to implementation, routing, authorization, localization, or motion invalidates downstream evidence.

## Missing Proof

- Current-byte baseline and candidate PNG captures.
- Compact and regular viewports.
- Arabic RTL and English LTR matched state.
- Light and dark appearance.
- Empty and populated/live states.
- Physical-device route/pop, language switch, permission revocation, and feed lifecycle.
- VoiceOver, Voice Control, Switch Control, Full Keyboard Access, AX5, increased contrast, Reduce Transparency, and Reduce Motion.
- Motion interruption, rapid refresh, disappearance/background cancellation, and measured frame pacing.
- Host-anchored independent reviewer/signature chain and verified V6 Visual Review Bundle.

## Next Evidence Action

Free host storage above the recorded 20% threshold, then use the connected iPhone 13 Pro Max and default DerivedData path to build/install the exact worktree. Capture the required baseline/candidate matrix, perform at most one pixel-evidence correction pass, profile the one motion phase, and submit current hashes and artifacts to an independent Proof V6 reviewer.
