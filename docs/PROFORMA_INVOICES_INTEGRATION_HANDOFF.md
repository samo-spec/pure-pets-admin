# Proforma Invoices integration

Date: 2026-10-10. Target: Pure Pets Admin and canonical Pure Pets Infra source.

## Scope and invariants

The workflow is draft creation/editing, scoped customer and sellable-item selection,
decimal calculations, saved-document preview, actual PDF export/share, and conversion
to a completed POS sale. Proformas live separately from completed transactions.
Saving, issuing, previewing, sharing, or cancelling a proforma must not reserve or
deduct inventory, collect payment, post income, or recognize accounting revenue.

The existing POS engine owns conversion effects. The sale and immutable
proforma-to-transaction link commit in the same Firestore transaction. Revision,
expiry, customer, branch, currency, current price, inventory identity, staff authority,
and duplicate-conversion checks apply at that boundary.

## Authority and integration

- Admin native route: `AdminRoute.proformaInvoices`, identifier `proformaInvoices`.
- Entry: POS supporting actions; existing route factory and UIKit host retained.
- Read permission: `pos.view` or `pos.sell`; write/conversion: `pos.sell`.
- Customer directory: existing `posCustomerCommand`; no direct directory writes.
- Infra callable: `proformaInvoiceCommand`, App Check enforced.
- Infra aggregate: `ProformaInvoices`, callable-only; client direct access denied.
- Actions: `context`, `list`, `get`, `catalog`, `save`, `issue`, `cancel`, `convert`.
- Mutation envelope: action, branchId, id, expectedVersion, commandId, payload.
- Decimal wire inputs: ASCII strings, prices two decimal places, ordinary single-unit
  quantities up to three; groups and individually identified/live inventory require
  integer quantities and exact identities. Existing commerce currency remains authority.
- Money snapshots: integer minor-unit totals; no client-authored persisted totals.
- Customer/product names and price snapshots come from scoped backend records.
- Tax defaults to zero; explicit rates are commercial inputs, not jurisdiction guesses.
- Drafts may be incomplete. Issue/conversion require a customer, items, and validity date.
- Status: draft, issued, converted, cancelled; expiry is derived from validity date.
- Issued edits create a new draft revision so previously exported PDFs remain identifiable.

## File ownership

- Admin models/service/editor: `Features/POS/ProformaInvoiceModels.swift`,
  `ProformaInvoiceService.swift`, `ProformaInvoicesView.swift`.
- PDF projection/render/preview/share: `Features/POS/ProformaInvoiceDocument.swift`.
- Existing customer picker: added proforma purpose, existing search/create authority.
- Route integration: `AdminRoute`, route destination, route factory, route bridges,
  Command Center POS actions, legacy dashboard fallback, explicit Xcode membership.
- Completed-receipt compatibility: preserve precise quantities and converted tax
  fields through receipt parsing, preview, export, and relevant refund presentation.
- Infra source/tests: canonical proforma arithmetic/commands plus focused POS and
  accounting integration. Existing unrelated dirty files must remain preserved.

## Validation and release boundary

Source integration is implemented. The focused source review and local backend
regressions have passed; native and deployed acceptance remain separate release gates.

Confirmed validation:

- `node tests/proformaCalculations.test.js`: PASS, exact unsigned decimal parsing,
  half-up cents, bounded discounts/rates, proportional largest-remainder allocation,
  cumulative ordinary/exact-unit refunds, balanced tax/revenue accounting, and
  fractional branch projection preservation.
- `node tests/accountingContract.test.js`: PASS, existing accounting validation,
  command/replay checks, POS income deduplication, and branch scope resolution.
- Swift frontend source parsing: PASS for the four new files and affected existing
  route/receipt/live-pet-return Swift sources. This is syntax validation, not native compilation.
- Xcode project and both string tables: `plutil -lint` PASS.
- Command Center V1 `verify-admin.mjs`: PASS for affected Admin sources, Xcode
  source registration, logical anchors, and no direct client audit writes.
- Paired Proforma localization key/format coverage and explicit Xcode Sources
  membership: PASS; 162 Arabic/English key pairs, including the captured-return
  allocation error. The task evidence contains the final referenced-key and hash report.
- Local Firestore emulator: existing POS integrity, real proforma handlers,
  accounting contract, proforma deny rules, and live-pet return release passed.
  This exercised persistence/replay/version checks, draft isolation, conversion
  races, audit/stock failure rollback, currency/price/permission rejection,
  fractional balances/refunds, and exact-unit captured tax allocations.
  The rules suite denied 18 direct-access attempts. The emulator exited with code
  zero and shut down. The final complete log is recorded in the evidence section.
- Changed Infra JavaScript syntax checks and the scoped diff whitespace check:
  PASS. Full Infra diff check has pre-existing trailing blank lines in
  `tests/chatMessages.test.js` and `tests/posCustomerDirectory.test.js`; those
  unrelated dirty files were preserved.

## Findings repaired during integration

- Kept proformas out of the existing pending-sale reservation path, which reserves
  inventory before completion. Only atomic conversion invokes completed-sale effects.
- Preserved fractional balances through shared branch projections, ordinary later
  sales/refunds, and inventory movement merges; packs/lots/exact pets retain their
  whole-unit constraints.
- Carried saved tax allocations into completed sales and balanced revenue/tax
  accounting and reversal entries; split refunds consume the captured cents exactly.
- Preserved precise quantities through the existing Objective-C receipt adapter,
  completed-receipt UI/PDF, history totals, and merchandise refund payloads.
- Removed integer full-refund inference and integer format strings from fractional
  receipt presentation; quantized refund requests to three places and exposed
  decimal partial-quantity input for eligible items.
- Kept fully discounted items returnable through quantity facts rather than marking
  the entire sale returned merely because its financial amount was refunded.
- Added immutable, protected, actor/branch-scoped command recovery. Mutations and
  accepted-but-unconfirmed results stay locked until safe replay or independent get.
- Guarded stale asynchronous reads and dirty/pending navigation; retained native
  safe-area/keyboard insets in both SwiftUI-route and legacy UIKit-host entry paths.
- Preserved captured net-plus-tax amounts in exact live-pet return previews and
  model decoding. Stable ASCII unit-ID ordering and largest-remainder allocation
  conserve saved cents; original gross prices still serve as immutable assertions.
  Zero-value physical returns use the existing no-reversal/manual-settlement path.
- Addressed the reported Swift 6 `sending Any` callable diagnostic: retained
  actor-owned dictionaries are serialized into immutable `Data`; a nonisolated
  decoder returns a fresh `sending Any` graph for Firebase. Callback results cross
  the continuation as `Data`, then decode on the main actor. The unchecked dictionary
  response wrapper was removed. The installed SDK signature was inspected directly;
  the change is source-validated, with native compilation still unverified.

## Operating workflow

Open **Command Center → POS → Proforma Invoices** (beside Receipts); the legacy
POS dashboard fallback opens the same module. Select an authorized branch, create
an incomplete draft, choose a customer and catalog/exact-unit choices, enter
quantities/discounts/tax/terms/notes, and save. Issuing requires customer/items/validity.
Saved revisions can be previewed in PDFKit and exported as an actual PDF URL through
the native share sheet. The PDF identifies draft/issued/converted/cancelled status,
revision, validity, currency, and its nonbinding quotation purpose.

An issued, unexpired quote can convert to a completed cash/card POS sale. Card here
records the operator-confirmed external payment under the existing POS contract; it
is not a new payment gateway. The saved quote's customer/items/prices are revalidated
at conversion. A deterministic sale identity prevents a second conversion across
operators/retries; the sale can be opened through the existing completed-receipt UI.

Decimal prices use the existing two-minor-digit commerce/accounting currency contract;
ordinary single-unit quantities support three places. Currency comes from canonical
commerce configuration and matching product records. Foreign-exchange conversion is
not introduced. Catalog prices remain authoritative; negotiated adjustments use
bounded line/invoice discounts. Tax defaults to zero and explicit operator rates apply
to each discounted line; no tax jurisdiction/rate is invented.

## Source-only release boundary

The user's source-only iOS validation choice persists: no native build, install,
launch, simulator, or device acceptance is authorized. Backend local/unit/emulator
checks are separate from deployment. No Firebase deploy, production mutation,
git push, or release is authorized.

Native build, rendered Arabic/English iPhone/iPad layouts, AX5, VoiceOver, dark mode,
actual PDF rendering, and physical-device behavior must be reported as UNVERIFIED
unless separately executed with authorization. Source parsing does not establish
those results. Backend tests do not prove that new functions or rules are deployed.

## Final evidence and certification

Admin task evidence:
`/var/folders/n6/5p16xph116n5w19rfp1yvvxh0000gn/T/purepets-proforma-integration-15bd4hsh`

- `admin-final-source-validation.json`: 19 source files inventoried and hashed;
  15 Swift files parsed; project/string lint; Admin static policy check; 162 paired
  localization keys and 156 referenced keys with format parity; four new Swift
  files registered in Xcode Sources. All these checks passed.
- `proforma-source-assertions.json` and `verify-proforma-source-contract.py`:
  32/32 executed source assertions for the real delegated authority, transaction,
  audit, conversion, recovery, stale response, PDF, and Swift 6 transport boundaries.
- `feature-ledger.json`, `ledger-compile-report.json`, `ledger-parity-report.json`,
  `ledger-tooling-limitations.json`: truthful Admin-only contract ledger, exact
  failed shape checks, skill requirements, and their diagnosis retained for review.
  Both compiler/parity commands exited with code one: 83 shape failures,
  76 observations, zero stale-hash errors. Certification remains blocked.
- `final-source-inventory.json`: 40 frozen source/test/localization/project identities
  independently checked for freshness; `proforma-contract-review.json` records
  the final wire, localization, recovery, concurrency, and proof boundaries.
- Baselines preserve existing dirty files. These reports are source evidence and
  do not certify native compilation, PDF rendering, or device behavior.

Backend task evidence:
`/var/folders/n6/5p16xph116n5w19rfp1yvvxh0000gn/T/proforma-infra-zu0ju98l`

- `FINAL_BACKEND_EVIDENCE.md`, `final-emulator.log`, `final-source.log`,
  `final-manifest.json`, `owned.patch` record the exact final backend files,
  commands, hashes, local runtime assertions, and baseline-scoped patch.
- Final emulator session 77671 exited with code zero and shut down all emulators.
  The final run includes the persisted half-cent conversion/refund regression:
  `1.15 × 80.3 = 92.35`, with the refund line also saved as 92.35 and stock restored.
- Exact-unit return case creation after real conversion retained gross 129.00
  and captured net-plus-tax 135.45. Eighteen direct quote/replay operations were denied.
- Actual handler tests execute against local Firestore; they do not prove deployed
  callable/App Check ingress. No Firebase deployment or production mutation occurred.

The installed Command Center ledger compiler reports 83 failures because its
source matcher requires inline named callable bodies, literal transition-arrow
tokens, and specific transaction variable shapes. The current integration uses
Firebase V2 `onCall`, delegated authorization and validation helpers, and the
existing POS transaction writer. The independent source review/assertions and
actual local handler/rules tests cover those real boundaries; the compiler report
is retained as failed and parity certification is not claimed.

The active [parity skill](/Users/mohammedahmed/.codex/plugins/cache/personal/command-center-nextgen-v1/1.0.0/skills/command-center-nextgen-v1-parity/SKILL.md) states: “A stale hash, mismatched payload, missing ordered
auth/audit relationship, direct-write fallback, permission drift, or missing client
operation blocks completion.” The [verify skill](/Users/mohammedahmed/.codex/plugins/cache/personal/command-center-nextgen-v1/1.0.0/skills/command-center-nextgen-v1-verify/SKILL.md) states: “A `blocked` or `not-run`
proof blocks release completion.” It also requires: “Treat every failure as a
finding. Do not weaken a permission, rule, audit, or verifier merely to turn a
result green.” Accordingly, source implementation and local backend validation
are delivered, while automated parity certification and native/deployed release
acceptance remain blocked/unverified. The verifier was not weakened.

## Continuation

No source finding remains open in the performed focused reviews. Preserve the
current source and evidence when continuing. The next release work is an authorized
physical-device build and Arabic/English iPhone/iPad acceptance, actual long/multipage
PDF preview/share, VoiceOver/AX5/Reduce Motion/dark-mode checks, and a separate
explicitly authorized Infra deployment followed by real callable/readback checks.
Automated parity certification needs a verifier that recognizes the existing
delegated canonical handler pattern; do not change authorization architecture to
satisfy a source regex.

Contract constraints: merge repeat selections into one line per product; ordinary
single merchandise supports three quantity decimals, while live/exact/lot/packaged
items use whole units. Currency follows the existing two-decimal platform authority;
there is no FX. Tax rates are explicit quote inputs with zero default. Card conversion
records the existing external/manual POS payment confirmation.

=== CHECKPOINT START ===
Checkpoint Name: Proforma source integration and local backend verification
Status: completed
What was finished:
- Admin draft/customer/catalog/totals/preview/PDF share/conversion workflow.
- Canonical separate persistence and atomic duplicate-safe actual-sale conversion.
- Fractional receipt/refund and exact-unit net/tax return compatibility.
- Swift 6 callable ownership boundary correction and final source verification.
Files created/updated:
- Admin Proforma sources, route/customer/receipt/return adapters, paired localization.
- Infra proforma/POS/accounting/inventory/return owners, rules/indexes, focused tests.
Routes / models / APIs added:
- AdminRoute.proformaInvoices; proformaInvoiceCommand; ProformaInvoices.
Known remaining work:
- Native build/device/PDF runtime and deployed acceptance remain UNVERIFIED.
- Automated parity certification remains blocked by the retained matcher report.
How to continue next:
- Start from the final source hashes and local proof reports above.
- Follow only separately authorized native and deployment validation workflows.
=== CHECKPOINT END ===

## Follow-up: legacy host permission denial — 2026-10-11

The attached screen showed the document workspace's local permission-denied state,
before any invoice callable request. The legacy UIKit `AdminProformaInvoicesHostingController`
had constructed `AdminSession(source: PPAdminSessionSnapshot())`: an empty snapshot,
without canonical UID, permission keys, or branch scope. The SwiftUI shell route
already supplied its authenticated session correctly.

The Proforma UIKit host now restores its session through the existing
`PPAdminSessionBridge.restoreCurrentSession` / `PPStaffAuth` authority before
mounting the document workspace. It shows a native loading indicator, rejects a
missing/error snapshot or an authenticated UID mismatch, guards concurrent/stale
restoration and duplicate mounting, and offers localized Retry/Back on failure.
The real Proforma permission checks remain in place. No account permission, backend
contract, rule, role bypass, or production data was changed.

Focused source verification passed: Swift frontend parsing of the host, document
workspace and route destination; Command Center static Admin policy; diff whitespace
check. Native compilation and runtime behavior remain UNVERIFIED under the user's
source-only validation choice.

Follow-up evidence and the pre-change baseline are stored at:
`/var/folders/n6/5p16xph116n5w19rfp1yvvxh0000gn/T/purepets-proforma-permission-repair-saa8sjyx`.
The prior frozen inventory describes the earlier integration revision; this repair
changes `AdminRouteBridges.swift` and this handoff. Use the follow-up source hash
and baseline patch for this revision.

## Follow-up: deployment registration and disabled Create — 2026-10-11

Firebase deployment source analysis failed before deployment because the lazy
`functions/index.js` export for `proformaInvoiceCommand` had no entry in the canonical
IAM operation manifest or generated registry. The original handler/emulator checks
did not exercise this export-discovery boundary. Exact coverage was 316 registered
operations for 317 exports; proforma was the only missing operation.

The canonical `iam/operation-manifest.json` now registers the callable at
`./proformaInvoices`, with workforce access, action-dependent existing permissions
(`pos.view`, `pos.sell`, `users.view`, `users.manage`), required audit/idempotency,
handler resource scope, and T3 risk for actual-sale conversion. Existing-handler
enforcement and unattested evidence states remain truthful. The generator refreshed
`functions/generated/iamOperations.js`; manifest hash pins in
`iam/consumer-checkouts.json` and the IAM ADR were updated together. Catalog grants,
existing operation metadata, policy lifecycle/activation, consumer checkout revisions,
client artifacts, handler authorization, App Check and conversion behavior are unchanged.

The new `functions/tests/proformaDeploymentDiscovery.test.js` runs the actual Firebase
SDK source loader with outbound network access blocked, compares all discovered
endpoint identities against the generated operation registry, and checks proforma's
callable/platform/region metadata. `functions/package.json` exposes
`test:iam:discovery` and includes it in the regular IAM gate. The IAM contract suite
also covers proforma registration, action permissions, risk/audit/idempotency metadata,
missing-export rejection, and wrong-module rejection.

The visible but disabled Admin Create button already has `pos.sell`; its readiness
guard additionally requires canonical branch currency/item-limit context. The
unavailable callable leaves that context nil, so removing the guard would create
an unsafe placeholder draft. Keep the guard. Successful deployment followed by the
existing Retry, pull-to-refresh, or reopening the workspace reruns context loading
and enables Create when loading/command/opening locks are clear. Deployment alone
does not trigger an automatic retry in an already-open workspace.

`ProformaInvoiceService.swift` now maps context-loading NOT_FOUND to the existing
localized unavailable/retry error rather than invoice field-validation copy.
Authentication/permission denial and other-action error mappings remain unchanged.
No new localized strings or layout changes were needed; Arabic/English strings and
RTL/LTR behavior remain through the existing localization system.

Executed validation:

- Canonical generator verify: PASS; all manifest pins agree, 317/317 exact exports.
- IAM policy contract: PASS; source and generated registration/negative cases covered.
- IAM cross-surface catalog parity: PASS, 9/9 checks. This does not supersede the
  earlier Command Center integration-ledger certification limitation.
- Actual Firebase SDK `loadStack` and the new npm discovery gate: PASS, 317 endpoints,
  including the proforma callable. No business handlers were invoked.
- Firebase index configuration and Storage helper regressions: PASS.
- Admin service Swift frontend parsing, focused Admin static check, scoped whitespace:
  PASS. Native compilation/runtime remain UNVERIFIED under source-only validation.
- Repository-wide function CPU-budget test: FAIL on existing one-CPU profiles for
  `imageSearch` and `lensAnimalIdentify`. It successfully loaded all exports before
  reaching that separate policy failure; the proforma profile remains fractional CPU.
  The CPU verifier and those runtime profiles were not changed by this repair.

Evidence and pre-change baselines:
`/var/folders/n6/5p16xph116n5w19rfp1yvvxh0000gn/T/purepets-proforma-registry-repair-o30b7pjd`.
This follow-up supersedes earlier source hashes for the edited service and handoff;
use the follow-up final inventory for the current revision.

No deployment, production mutation, native build, install or launch was performed.
The original user deployment command can be rerun from the Functions directory.
Deployed callable/App Check acceptance and an actual Create tap remain UNVERIFIED.

=== CHECKPOINT START ===
Checkpoint Name: Proforma export discovery repair
Status: completed
What was finished:
- Canonical IAM registration, generated registry and consistent manifest hash pins.
- Dedicated actual Firebase source-discovery regression in the regular IAM gate.
- Disabled Create dependency traced; localized context-unavailable copy corrected.
Files created/updated:
- Infra IAM manifest/checkouts/ADR/generated registry and focused contract/discovery tests.
- Infra Functions package scripts; Admin proforma service; this handoff.
Routes / models / APIs added:
- No new route, permission or backend contract; existing proforma callable registered.
Known remaining work:
- User-run deployment and deployed context/Create verification remain UNVERIFIED.
- Existing global CPU-budget failures and prior native/parity acceptance boundaries remain.
How to continue next:
- Rerun the original deployment command, then Retry or reopen Proforma Invoices.
- Keep canonical context and staff/branch authorization guards in place.
=== CHECKPOINT END ===
