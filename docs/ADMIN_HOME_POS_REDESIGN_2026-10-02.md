# Admin Home POS redesign — 2026-10-02

Status: implemented and source-reviewed. Native build, rendering, accessibility traversal, and interaction validation are **UNVERIFIED**. This document is not release certification.

## Scope and direction

Rebuilt only the Home Point of Sale presentation in `PurePetsAdmin/Features/CommandCenter/AdminCommandCenterScreen.swift`, plus its English and Arabic localization entries. The existing SwiftUI island and Objective-C navigation bridge remain the integration boundary.

The new composition gives the register one prominent, lightly tinted action surface. Receipts, expenses, and Wanted Pets use separate native button rows. Branch and cashier identity precede the actions; an expandable sales summary follows them. Existing `AdminSurface` colors and dynamically scaled Beiruti typography supply the product identity. Press feedback changes opacity without moving hit targets; ambient scanning, pulsing decoration, fixed-height text, and competing colored panels were removed.

iPhone uses concise supporting rows and initially collapsed sales details. iPad retains fuller descriptions, initially expanded details, and Command-N/B/H/E shortcuts. Two columns require a measured section width of at least 740 points and a non-accessibility text size; narrower windows and accessibility sizes stack. Intrinsic-width summary/metric candidates fall back to multiline vertical arrangements. Decorative icons yield space at accessibility text sizes.

## Behavior retained

| Existing capability | Final integration |
| --- | --- |
| Register / iPad Quick Scan | Existing `pos` route; original route authority remains responsible for access |
| Invoices and receipts | Existing `posHistory` route |
| Wanted Pets | Existing `wantedPets` route and `canOpenWantedPets` gate; `pos.wantedPets.entry` retained |
| Add expense | Existing `CommandPOSQuickExpenseSheet` full-screen presentation, branch label, and accounting callback |
| iPad automation | `admin.command.pos.card` identifier retained |
| Shift figures | Sales, receipts, average receipt, refunded-receipt count, cash/card amounts and split |
| Refresh / disclosure | Native buttons, current-branch refresh, retained phone/pad disclosure defaults |

The complete expense implementation and all source before/after the POS boundary are byte-equivalent to the task baseline. Firebase services, collection identities, permission checks, models, and the UIKit duplicate-push guard were not changed. Existing figures still derive from the service's latest 250 branch receipts, filtered to today; this change does not establish complete accounting totals.

## Readback correction

The previous shared fetching flag could drop a new-branch request and accept the previous branch's callback. Each request now captures a UUID and branch identity. Branch changes clear prior figures/freshness and invalidate old callbacks, including an A → B → A switch. Removing the active branch clears its figures. Failed refreshes retain the last successful snapshot and timestamp, show localized failure/retained-data feedback, and offer an adjacent retry button. Only successful responses advance the timestamp.

## Localization and accessibility

Added 28 paired, unique, nonempty `AdminPOS_Home_*` keys. Existing localization file bytes were preserved. Layout direction, leading alignment, and navigation arrows follow the selected app language; numeric amounts and times keep a local left-to-right direction. Buttons provide localized labels, hints, selected disclosure state, and stable identifiers. Targets are at least 44 points; refresh and disclosure controls are at least 48 points. Press/disclosure animation honors Reduce Motion. Semantic colors support the existing light/dark palettes and increased-contrast border treatment.

These are implemented source properties. AX5 appearance, mixed Arabic/currency rendering, VoiceOver focus order, dark-mode contrast, split-view fitting, and touch/keyboard behavior still require native validation.

## Validation evidence

- Swift frontend syntax parsing: passed. This is not a typecheck, app build, or device run.
- `plutil -lint`: both localization files passed.
- Command Center Admin source validator: passed for the exact changed Swift source.
- Command Center package and interpreted-scope validation: passed.
- Scoped `git diff --check`: passed.
- Baseline comparison: non-POS Home source and the expense workflow unchanged; original localization bytes retained.
- Two isolated CodeRabbit reviews: zero findings. The second review preceded the final decorative-icon accommodation for accessibility sizes; the final independent source review covered that accommodation.
- Final independent source review: no unresolved critical, high, or medium findings identified.
- App build/device/runtime checks: not run; user instructions require explicit build authorization.

Raw task resolution incorrectly classified the artistic words “create” and “transition” as a backend contract change. The original request/result were retained, and a separately identified implementation-scope description resolved to Admin-only, no backend change. The original and interpreted task digests are not interchangeable. No verifier or authority boundary was weakened.

Temporary check records and raw review output are in `/tmp/pp-admin-home-pos-20261002/`. Existing unrelated dirty changes were not edited by this task. A concurrent change to `PPAccessoryEditorView.swift` appeared after the initial hash comparison and was left untouched.

## Final implementation hashes

| File | SHA-256 |
| --- | --- |
| `AdminCommandCenterScreen.swift` | `0c5f6af25b2d8e2771ac90f7cd0823a161e4a50784e46cc6012e94300a47051f` |
| `ar.lproj/Localizable.strings` | `0030d0c1c03307a2de9b76b4942d96cea5d7a290eabe63d2abff62d8f1bee485` |
| `en.lproj/Localizable.strings` | `c0f345cde57db0ad645e3487901da678ef08417055f36c5c6ab1f5a10428e31d` |

Next gate: authorized native validation of both intended layouts, Arabic/English, maximum accessibility text, VoiceOver, Reduce Motion, dark mode, permission states, rapid branch changes, failed refresh recovery, all routes, and iPad keyboard shortcuts. No production deployment was performed.
