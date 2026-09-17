# Pury Admin Premium Results Redesign Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Turn Pury's Admin iOS experience into a brand-consistent operational assistant that renders authoritative structured results instead of tool traces and never lets conversation content hide under the composer.

**Architecture:** Keep `puryAdminChat` and all existing navigation/permission contracts unchanged. Add a Pury-local brand token layer to the existing avatar file, sanitize only presentation-layer assistant prose, reuse backend `structuredData` for cards/records, and move the composer into SwiftUI safe-area ownership.

**Tech Stack:** SwiftUI, UIKit bridge, existing AdminSurface/AdminType/PPBrandFont, existing Pury models/service/store, Python static contract verification.

**Spec:** `docs/superpowers/plans/2026-09-17-pury-admin-premium-results-redesign-spec.md`

## Global Constraints
- Preserve all existing Pury callables, routes, permissions, confirmation behavior, and deep links.
- Do not hardcode assistant answers or synthesize fake backend data.
- Do not run `xcodebuild` or a simulator.
- Preserve Arabic RTL, English LTR, Dynamic Type, VoiceOver semantics, safe areas, and Reduce Motion.
- Preserve existing uncommitted user work; do not commit or push this dirty working tree.

---
### Task 1: Lock the Pury presentation contract with failing static tests

**Files:**
- Modify: `scripts/pury_contract_static_test.py`
- Test: `scripts/pury_contract_static_test.py`

**Interfaces:**
- Consumes: current Pury UI/avatar/shell source.
- Produces: assertions for `PuryBrand`, `PuryResponseDisplaySanitizer`, safe-area composer ownership, and launcher brand token usage.

- [ ] Add assertions that require a Pury-local rose palette, trace sanitizer, `.safeAreaInset(edge: .bottom`, and `PuryBrand` usage in `AdminAppShell.swift`.
- [ ] Run `python3 scripts/pury_contract_static_test.py` and verify failure is caused by the missing redesign contract.

### Task 2: Implement presentation sanitization and premium structured-result hierarchy

**Files:**
- Modify: `PurePetsAdmin/Features/Pury/UI/PuryAssistantSheetView.swift`
- Test: `scripts/pury_contract_static_test.py`

**Interfaces:**
- Consumes: `PuryMessage.metadata.structuredData`, `PuryCard`, `PuryDataBlock`.
- Produces: `PuryResponseDisplaySanitizer.cleanNarrative(_:hasStructuredData:)` and structured result surfaces driven only by server metadata.

- [ ] Add the presentation sanitizer that removes TOOL CALL/TOOL RESPONSE blocks, fenced JSON, and markdown artifacts without manufacturing domain data.
- [ ] Update `purySmartAnswerView` to use cleaned supporting prose and promote valid server cards/blocks ahead of technical narrative.
- [ ] Add a compact structured-result header/count when structured records are present.
- [ ] Run the static contract test and keep it green before continuing.
### Task 3: Move composer to safe-area ownership and align assistant identity

**Files:**
- Modify: `PurePetsAdmin/Features/Pury/UI/PuryAssistantSheetView.swift`
- Modify: `PurePetsAdmin/Features/Pury/UI/PuryAvatar.swift`
- Test: `scripts/pury_contract_static_test.py`

**Interfaces:**
- Consumes: `PuryBrand` shared palette and existing conversation store state.
- Produces: bottom composer safe-area inset and consistent idle/thinking Pury identity colors.

- [ ] Add `PuryBrand` static color tokens derived from the PuryV1 rose/pink asset.
- [ ] Replace the overlaid composer with `.safeAreaInset(edge: .bottom)` and reduce manual scroll padding.
- [ ] Replace Pury-identity emerald hardcodes with PuryBrand tokens while leaving semantic live/success/warning/error colors intact.
- [ ] Update idle/thinking avatar aura/core/ring colors to rose/pink with restrained violet during inference and Reduce Motion preserved.
- [ ] Run the static contract test again.

### Task 4: Rebuild the floating Pury launcher around the shared identity

**Files:**
- Modify: `PurePetsAdmin/App/AdminAppShell.swift`
- Test: `scripts/pury_contract_static_test.py`

**Interfaces:**
- Consumes: `PuryAvatar` and `PuryBrand`.
- Produces: safe-area-aware frosted launcher with Pury rose tint/edge/aura and the existing permission gate/action.

- [ ] Replace launcher identity colors with shared PuryBrand tokens and preserve its current permission and presentation behavior.
- [ ] Keep a minimum 44pt interactive height and current bottom-clearance ownership.
- [ ] Run the static contract test again.
### Task 5: Verify the focused redesign without claiming unavailable runtime proof

**Files:**
- Review: all files changed by Tasks 1–4

**Interfaces:**
- Consumes: final working tree.
- Produces: source/static verification evidence and explicit runtime-proof boundary.

- [ ] Run `python3 scripts/pury_contract_static_test.py` fresh and require exit 0.
- [ ] Run the Command Center NextGen Admin static verifier from the umbrella skill package; record any tool/package blocker exactly.
- [ ] Run `git diff --check` and inspect `git diff --` for the target files to catch whitespace, accidental unrelated edits, and contract regressions.
- [ ] Confirm no `xcodebuild`, simulator, deployment, production mutation, commit, or push occurred.
- [ ] Report source/static evidence separately from physical-device/rendered evidence, which remains not run unless explicitly authorized and available.