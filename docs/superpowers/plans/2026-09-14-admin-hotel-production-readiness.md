# Admin Hotel Production Readiness Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans and TDD for every behavior change.

**Goal:** Make Pure Pets Hotel in the Admin app operationally correct, explainable, secure, accessible, and release-verifiable from reservation through checkout.

**Architecture:** Keep Firebase Hotel callables as authoritative writers/read models. Refactor Admin into typed operational projections that preserve backend verdicts instead of collapsing them into UI booleans. Fail closed on identity, permission, clinical, capacity, and lifecycle uncertainty.

**Tech Stack:** SwiftUI/UIKit, Firebase Auth/Firestore/Functions, Node.js Firebase Functions, Firestore Rules, XCTest, Node contract tests.

**Global Constraints:** Scope is Admin Hotel plus Hotel backend/rules only. Preserve unrelated dirty files. No direct client writes for protected Hotel state. Arabic/RTL and English/LTR remain first-class. No completion claim without fresh build/test evidence.

---

### Task 1: Typed room availability and reception explainability
- RED: prove rejection reasons survive the callable-to-UI boundary and bird suites do not default to dog.
- GREEN: add typed availability verdict/snapshot models and canonical wing-to-species defaults.
- REFACTOR: check-in shows assignable rooms first and unavailable rooms with precise reasons; refresh/error/empty are distinct states.
- VERIFY: unit/static contracts plus simulator build.

### Task 2: Reservation identity and booking integrity
- RED: prove unknown/guest customer never maps to a hard-coded account and explicit Hotel classification survives payload construction.
- GREEN: fail closed on unresolved customer identity and preserve the selected accommodation type/wing intent.
- VERIFY: reservation contract tests and negative cases.
### Task 3: Intake and checkout safety invariants
- RED: prove readiness progress and button eligibility share the same required checks, including diet/allergy confirmation.
- GREEN: centralize readiness evaluation and keep clinical/deposit requirements explicit and explainable.
- VERIFY: check-in/out direct, edge, replay, early checkout, belongings, billing, incident, and medication cases.

### Task 4: Suites, rates, capacity, and housekeeping truth
- RED: prove room cards inherit canonical type rates when unit rate is absent and special-wing species defaults never corrupt.
- GREEN: reconcile room/type metadata and separate physical status from guest-window assignability.
- VERIFY: capacity, shared occupancy, cleaning, inspection, maintenance, blocked, inactive, and back-to-back windows.

### Task 5: Permissions, rules, and action completeness
- Inventory every Hotel button/action and map UI capability -> callable action -> backend permission -> rules/read authority.
- Add fail-closed guards where Admin exposes an action without the corresponding capability.
- Run Hotel domain, permission parity, and Firestore rules negative tests.

### Task 6: Care/tasks, stay detail, billing, and failure recovery
- Validate care task transitions, health observations, billing visibility, settlement, stay refresh, command replay, transport errors, and stale projections.
- Fix only confirmed defects with red-green tests.

### Task 7: Apple-grade interaction/accessibility hardening
- Audit iPhone/iPad layouts, RTL/LTR, Dynamic Type, VoiceOver semantics, hit targets, reduced motion, loading/error/empty/conflict states, destructive confirmations, and double-submit prevention.
- Preserve the existing authored visual language while removing misleading or non-operational decoration.

### Task 8: Release evidence and independent review
- Run fresh Admin simulator build/tests and Hotel backend/rules suites.
- Inspect scoped diffs for regressions and unrelated edits; run code-review workflow on the final Hotel diff.
- Record unresolved environmental blockers explicitly; release-ready requires zero known P0/P1 Hotel defects and fresh evidence.