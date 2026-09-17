# Pury Admin Premium Results Redesign Spec

## Scope
Redesign only the existing Pury experience in Pure Pets Admin iOS: structured answer presentation, assistant-screen layout, shared Pury avatar identity, and the floating launcher. Preserve current routes, permissions, backend contracts, callables, and operational semantics.

## Result Presentation
- Never present TOOL CALL, TOOL RESPONSE, fenced JSON, or raw tool payloads in the normal operator UI.
- Treat backend `structuredData` as the authoritative source for premium result cards and record surfaces.
- Preserve useful assistant prose after removing execution traces and markdown artifacts.
- Keep technical identifiers available only when operationally useful; render IDs directionally LTR and copyable.
- Keep existing deep links and confirmation flows intact.

## Screen Layout
- Replace the ZStack-overlay composer with a real bottom safe-area inset so conversation content cannot hide underneath it.
- Keep one calm header anchor: Pury identity, status, language, clear action.
- Reduce active context to a compact branded context rail/chip.
- Preserve Arabic RTL, English LTR, Dynamic Type, VoiceOver, 44pt targets, safe areas, and Reduce Motion.
## Pury Brand Identity
- Base the Pury-local palette on the actual `PuryV1` asset: deep rose/crimson through luminous pink.
- Pink/rose identifies Pury. Do not use emerald as Pury's identity color.
- Keep green, amber, red, blue, and violet available for operational semantics such as success/live, warning, destructive/error, information, and active inference.
- Use the shared Pury palette in the avatar, assistant identity surfaces, composer focus/send affordance, and floating launcher.

## Verification Boundary
- Do not use `xcodebuild` or a simulator.
- Extend the existing `scripts/pury_contract_static_test.py` with source-contract assertions and run it red→green.
- Run the Command Center Admin verifier and inspect the final diff.
- Device/rendered evidence remains separate and cannot be claimed from source-only checks.