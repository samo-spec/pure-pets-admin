# Admin alert helper — SwiftUI reinvention

Date: 2026-10-11. Scope: `PurePetsAdmin/Utilities/PPAlertHelper`, its presentation bridge, project registration, and paired localization. No route, session, permission, Firebase, or service changes.

## Product decision

Use a leading reading column with a small semantic signature, a large title, explanatory text, a persistent input label where applicable, and an adaptive action shelf. Short alerts sit within reach at the bottom of compact windows; wide windows center a bounded 520-point surface. Arabic mirrors logical alignment and action placement. English uses the same hierarchy in LTR.

Three directions were considered: a centered status monument, a full-width bottom command sheet, and a compact reading surface with reachable actions. The reading surface preserves native modal attention while accommodating long operational explanations, short acknowledgements, and editable prompts without expanding the rest of the app's navigation architecture.

The surface uses the existing Beiruti fonts and dynamic `UIColor.pp*` tokens. Text, controls, and colors communicate state independently of haptics. The input boundary uses readable semantic text/accent colors; the surface itself is opaque in both appearances.

## Ownership and behavior

- `PPAlertHelper.h`: all existing public selectors and Swift names retained. Nullability now documents the existing optional presenter/icon behavior. Direct `PPAlert` construction follows UIKit's main-thread convention.
- `PPAlertHelper.m`: Objective-C action model and compatibility facade. Terminal helpers forward to main before creating the adapter. The previously declared but unimplemented automatic alert and destructive text-input methods now have implementations.
- `PPAlertSwiftUI.swift`: internal `@objc` presenter, request model, window-scoped FIFO lanes, transient `UIHostingController`, and SwiftUI surface. It does not authenticate, authorize, navigate, or mutate backend data.
- Xcode project: one Swift file registered with file reference, group membership, build-file record, and app Sources membership.
- Arabic and English strings: one paired fallback input-label key; existing semantic alert keys reused.

Action identity remains its original array index. Confirm/cancel roles are explicit. Three-action confirmations honor every supplied `UIAlertActionStyle` and have an explicit keyboard default derived only from their declared primary action. Existing dedicated destructive confirmations retain their intentional confirm default. Secondary or tertiary destructive choices cannot replace the primary Return action. An all-empty three-action request gets a localized acknowledgement without synthesizing any caller action.

Callbacks run on main after controlled dismissal and are guarded against repeated selection. Text is trimmed; confirmed empty input remains an empty string, while prompt cancellation remains nil/false through the existing facade. Legacy placeholder-only confirmation overloads remain confirmations. Secure entry and the supplied keyboard type survive the bridge.

Outside tap, Escape, and VoiceOver escape use the actual cancel choice and remain unavailable for single-acknowledgement alerts. Unexpected dismissal or scene closure can cancel but cannot synthesize confirmation. Dismissal retains its presentation lane until UIKit completion, including scene teardown. Explicit-source requests stay in their source window; orphaned queued sources cancel instead of moving to a different scene. Pending lanes resume on application activation, scene activation, or window visibility.

## Layout, accessibility, and motion

There is one mounted input instance inside one measured `ScrollView`. The surface caps its height to the available safe area. Content and all actions remain scrollable when long copy, AX5 fonts, landscape, or the keyboard need more space. `ScrollViewReader` brings the input into view as focus or available height changes. There is no duplicated fitting-versus-scrolling text field, manual keyboard offset, or minimum font shrinking.

Title and body use literal caller text and logical leading alignment. Locale/direction use `Language`; live language notifications arrive on main. Free text follows the app direction, while email, URL, phone, and number keyboard types keep local LTR input. The input has a persistent visible label and matching accessibility label. Action labels wrap and have a minimum 52-point height. Accessibility-size actions stack vertically. Only the heading owns initial VoiceOver focus; the hosting view is modal, and prior focus restoration precedes callback-driven navigation.

UIKit owns the finite cross-dissolve presentation/dismissal. Selection waits until presentation is ready. Button pressure uses a small immediate transform plus a tonal response; Reduce Motion removes the transform live. No ambient loop, delayed action, network work, polling, or independent keyboard animation is added.

## Validation evidence and limits

Passed source checks:

- `swiftc -frontend -parse` for the Swift presenter/surface (syntax only).
- `plutil -lint` for the Xcode project and both strings files.
- Command Center `verify-admin.mjs` for the header, facade, and Swift source.
- Public header/implementation selector parity and exact internal Objective-C/Swift bridge-selector matching.
- Four Xcode membership records added; the existing dirty project lines preserved.
- Existing Arabic/English strings preserved as byte prefixes; new/reused alert keys present in both languages.
- `git diff --check` on the affected files.
- Independent focused lifecycle/bridge and accessibility/layout source review. Reported callback lifetime, implicit destructive default, stale-source fallback, heading focus, input boundary, notification scheduling, and scene-resume issues were repaired.

The raw Command Center request classifier recognizes the Admin source path but falsely flags generic redesign wording about transitions as a backend contract change. Source ownership review establishes this task as Admin presentation only; no backend slice was edited or deployed. This classifier result is not used as release certification.

No Xcode build, installation, launch, Simulator, or native runtime check was run. Workspace policy requires explicit build/run authorization and the approved connected iPhone workflow. No claim of rendered visual quality, type-check/build success, runtime VoiceOver, or measured performance follows from syntax/static checks.

Required native acceptance matrix (all **UNVERIFIED**):

| Scenario | Required observation |
| --- | --- |
| Arabic RTL / English LTR / mixed text | Reading order, alignment, action positions, numeric/email field direction |
| Light / dark appearance | Text and input-boundary legibility, semantic state independent of color |
| Compact portrait / landscape / wide window | Bounded surface, safe areas, no clipped copy or actions |
| AX5 / long title-body-action text | Full readability and reachable scrolling actions |
| Secure / numeric / email / ordinary input | Initial text, focus, cursor, keyboard avoidance, Return and trim behavior |
| VoiceOver / keyboard / pointer | Modal isolation, heading-first reading, labeled field, Escape, primary action identity, focus return |
| Rapid taps / queued alerts / callback navigation | Exactly one selected callback after dismissal; no competing presentations |
| Background / foreground / scene closure | Queue resumes correctly; orphaned/closed scenes never confirm |
| Reduce Motion and live setting change | Same meaning and actions, no pressure scaling when enabled |
| Device performance | Smooth bounded transitions, no repeated work, no retained dismissed host |

Temporary baseline and static evidence location: `/tmp/pp-alert-swiftui-20261011` (ephemeral). The implementation is ready for the native verification stage; Apple-grade/production-readiness certification remains unverified until that evidence exists.
