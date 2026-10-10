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

Implementation and verification are in progress. This file will be updated with exact
commands, results, findings repaired, and remaining runtime evidence before handoff.

The user's source-only iOS validation choice persists: no native build, install,
launch, simulator, or device acceptance is authorized. Backend local/unit/emulator
checks are separate from deployment. No Firebase deploy, production mutation,
git push, or release is authorized.

Native build, rendered Arabic/English iPhone/iPad layouts, AX5, VoiceOver, dark mode,
actual PDF rendering, and physical-device behavior must be reported as UNVERIFIED
unless separately executed with authorization. Source parsing does not establish
those results. Backend tests do not prove that new functions or rules are deployed.
