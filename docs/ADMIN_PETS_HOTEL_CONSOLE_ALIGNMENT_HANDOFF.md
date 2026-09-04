# Pure Pets Admin — Pets Hotel Console Alignment Handoff

Date: 2026-09-04
Project: Pure Pets Admin
Scope: Admin App Hotel section and directly related Admin route, authorization, localization, and Command Center files only
Firebase project: `pure-pets-49199`

## Goal

Align the Admin App Pets Hotel surface with the existing Console/Infra Hotel backend contract, repair the Command Center Hotel entry, and make the Hotel back control use the real UIKit navigation owner.

## Authority inspected

- Infra Hotel permission catalog and role defaults: `Pure Pets Infra/functions/constants.js`
- Infra Hotel authorization map: `Pure Pets Infra/functions/hotel/authz.js`
- Infra operational projections: `Pure Pets Infra/functions/hotel/readOperations.js`
- Infra check-in/out gates and transactional checkout behavior: `Pure Pets Infra/functions/hotel/stayDomain.js`, `stayCommands.js`
- Infra care task transition authority: `Pure Pets Infra/functions/hotel/careCommands.js`, `taskDomain.js`
- Console Hotel data-access pattern: `Pure Pets Console/src/services/petsHotelService.ts`
- Console front-desk verification behavior: `Pure Pets Console/src/pages/PetsHotelOperations.tsx`

Console and Infra were inspected read-only. No Console or Infra source was changed.

## Root causes found

1. `AdminCommandCenterScreen` emitted route tag `hotel`, but `AdminDashboardViewController` had no `hotel` mapping in `pp_viewControllerForDashboardTag:`. The tap therefore resolved to `nil`.
2. `AdminPetsHotelHubView` called SwiftUI `dismiss()` while hosted inside a UIKit navigation controller. That environment action had no owning SwiftUI presentation to dismiss, so the custom back control did nothing.
3. `AdminRoute.hotel` accepted unrelated permissions, including `services.*` and `dashboard.view`, plus a nonexistent `hotel.manage` permission. Infra requires the exact `hotel.view` capability.
4. Admin's local staff permission catalog omitted the complete Hotel permission module, causing default role behavior to drift from Infra.
5. The Hotel view model queried without a required branch, substituted a fake `default` branch, swallowed callable failures, and populated hard-coded rooms, customers, stays, and reservations when backend results were empty.
6. Check-in/out verification booleans defaulted to `true`, allowing the UI to submit attestations the operator never made.
7. Checkout issued a second accommodation-status command even though `hotelStayCommand` already releases the room to `cleaning` transactionally. This could partially fail for a staff member who has `hotel.checkout` but not `hotel.accommodations.manage`.
8. Room assignment used only the current room status instead of the backend `availability` projection for the reservation window.
9. Hotel mutations generated a new command ID for every retry, unlike the Console's stable logical-intent retry behavior.

## Completed changes

- Added the missing `hotel` route mapping to `AdminPetsHotelHostingController`.
- Added fail-closed `hotel.view` gating at the Command Center card and controller-resolution boundary.
- Injected a UIKit-aware dismissal callback using `PPAdminNavigationFallback.popOrDismiss(from:)`.
- Restricted `AdminRoute.hotel` to `hotel.view`.
- Added Infra-matching fine-grained Hotel permission constants and aligned Hotel-related default-role behavior.
- Moved accommodation listening behind `AdminPetsHotelService`, branch-scoped and capped to 200 rows.
- Kept stays, reservations, command-center data, availability, and stay dossiers on `hotelReadOperations` projections.
- Removed fake branch substitution and all production fallback Hotel rooms, stays, people, phone numbers, prices, and reservations.
- Added explicit branch-required, loading, empty, partial-error, permission, and retry behavior.
- Prevented stale branch requests from overwriting the newly selected branch.
- Corrected reservation billing parsing to use `pricing` and `billingSummary`, respecting backend redaction when billing permission is absent.
- Added missing canonical wing, room-status, reservation-status, and care-task values.
- Changed check-in/out verification defaults to `false` and exposed the backend-required confirmations.
- Changed room selection to use the backend `availability` verdict for the full stay window.
- Removed optimistic fabricated stay/room state; successful commands reload authoritative projections.
- Removed the redundant post-checkout room mutation; transactional checkout remains the sole lifecycle authority.
- Made room status updates await callable success before dismissing.
- Prevented generic care-task actions for medication tasks and removed client-side optimistic completion.
- Added durable logical-intent command IDs that survive ambiguous transport failures and clear after success or terminal errors.
- Reset the selected Hotel tab to Overview when `hotel.care.view` is absent or revoked, preventing an inaccessible hidden Care tab from remaining active.

## Files changed

- `PurePetsAdmin/AdminDashboardViewController.m`
- `PurePetsAdmin/App/AdminRouteBridges.swift`
- `PurePetsAdmin/Shared/Routing/AdminRoute.swift`
- `PurePetsAdmin/Features/CommandCenter/AdminCommandCenterScreen.swift`
- `PurePetsAdmin/Features/Hotel/AdminPetsHotelHubView.swift`
- `PurePetsAdmin/Features/Hotel/AdminPetsHotelModels.swift`
- `PurePetsAdmin/Features/Hotel/AdminPetsHotelService.swift`
- `PurePetsAdmin/Features/Hotel/AdminPetsHotelViewModel.swift`
- `PurePetsAdmin/Features/Hotel/AdminPetsHotelCheckInOutViews.swift`
- `PurePetsAdmin/Features/Hotel/AdminPetsHotelStayDetailSheet.swift`
- `PurePetsAdmin/UsersSection/SecFil/PPStaffAuth.h`
- `PurePetsAdmin/UsersSection/SecFil/PPStaffAuth.m`
- `PurePetsAdmin/ar.lproj/Localizable.strings`
- `PurePetsAdmin/en.lproj/Localizable.strings`
- `docs/ADMIN_PETS_HOTEL_CONSOLE_ALIGNMENT_HANDOFF.md`

## Security and data behavior

- UI visibility is convenience only; Infra callables remain authoritative.
- Hotel entry requires active staff with `hotel.view`.
- Check-in requires `hotel.checkin`.
- Checkout requires `hotel.checkout`.
- Room status changes require `hotel.accommodations.manage`.
- Care dossier reads require `hotel.care.view`; task execution requires `hotel.task.execute`.
- Billing display requires `hotel.billing.view` and remains hidden when the projection redacts it.
- Medication task transitions remain on the dedicated medication command path.
- All mutations remain callable-only and inherit server validation, branch scope, transactions, idempotency receipts, and audit logging.

## Validation status

- Infra/Admin Hotel permission catalog parity: **passed**. A full exact comparison found 29 canonical `hotel.*` keys on each side, with no Infra-only or Admin-only key.
- Changed Swift source syntax parse: **passed** with `swiftc -frontend -parse` for `AdminPetsHotelModels.swift`, `AdminPetsHotelViewModel.swift`, `AdminPetsHotelCheckInOutViews.swift`, and `AdminPetsHotelStayDetailSheet.swift`.
- Admin Command Center static verifier: **passed** with no errors or blocked checks (`native-project-markers`, `changed-source-policy`).
- Final scoped semantic review: **approved** with no actionable defects in the Hotel models, view model, check-in/out sheet, detail sheet, or this handoff.
- Arabic/English string-table syntax: **passed** with `plutil -lint`.
- Scoped Hotel `Language.get(...)` localization coverage: **passed**. All 109 referenced keys exist in Arabic and English, with zero duplicate `Hotel_*` keys in either table.
- Behavior-ledger JSON: **valid** at `.kiro/evidence/admin-hotel-console-alignment-behavior-ledger.json`; all reviewed Infra source hashes are current.
- Behavior-ledger compile and parity verification: **not passable with the installed static verifier**. Both commands reached all three audit operations (check-in, checkout, and `care_operations`) and failed only because `hotelStayCommand` delegates its auth/validation/transaction/audit chain to `executeHotelStayCommand`, while `hotelReadOperations` delegates permission resolution to `resolveHotelReader`. The verifier requires those checks directly in the outer callable body. No Infra wrapper was changed merely to satisfy that implementation-detail assumption, and no pass result is claimed.
- Whitespace/error-marker validation: **passed** with scoped `git diff --check`; the behavior-ledger JSON also parses successfully.
- Firebase deployment: **not run and not requested**.
- Xcode build, physical iPhone install/launch, and rendered-route proof: **not run**. This Admin task has no explicit physical-device approval; repository policy prohibits generic Admin `xcodebuild` verification. No simulator was used.

## Continuation fix log

1. **Resolved (2026-09-04) — Reservation stay identity.** `AdminHotelReservation` now accepts only non-empty server-projected `stayIds`; it never falls back to `petIds`. Check-in therefore remains fail-closed through `Hotel_Err_StayRequired` when no real stay identifier is available.
2. **Resolved (2026-09-04) — Belongings quantity.** Check-in emits and parsing prioritizes the canonical `quantity` field; historical `count` is retained only as a read fallback, so quantities are no longer silently reduced by Infra's default.
3. **Resolved (2026-09-04) — Emergency-contact omission.** Check-in trims the customer-derived name and phone, sends an emergency-contact object only when both are complete, and otherwise omits the field so Infra can retain the stored stay contact.
4. **Resolved (2026-09-04) — Care board hydration.** Branch-scoped, capability-gated `care_operations` tasks now hydrate the matching in-house stays using the active load generation; malformed task/stay identifiers are ignored and a care-projection failure remains an explicit partial-load error.
5. **Resolved (2026-09-04) — Conditional acknowledgements.** Check-in now requires medication and deposit confirmations only when the authoritative stay/reservation projection indicates they apply; diet remains recorded but is not a blocker. Checkout now requires belongings, incident, and medication acknowledgements only when their authoritative counts are positive, while health, room inspection, and handover remain universal. Billing-redacted deposits remain unknown to the client and are still enforced by Infra.
6. **Resolved (2026-09-04) — Authoritative medication readiness.** The check-in sheet now matches the selected reservation only to its server-projected first `stayId`, reservation, and pet before it exposes or gates medication confirmation. It no longer uses the reservation projection's absent medication-declaration field; no matching operational-stay projection leaves submission disabled rather than bypassing the server gate.
7. **Resolved (2026-09-04) — Dossier checkout counters.** `loadStayDossier` now normalizes documented nested `stay.counters` fields from the `stay_operational_summary` projection before model parsing. Belongings, critical incidents, and pending medication therefore retain their authoritative positive counts after a detail refresh and keep their conditional checkout acknowledgements visible and blocking.
8. **Resolved (2026-09-04) — Projection-preserving dossier merge.** A stay dossier now overlays only its authoritative status, room, pet, and counter fields onto the existing richer operational-stay projection. Customer/contact, billing, branch, room metadata, and check-in readiness are no longer blanked or replaced by omitted dossier fields.
9. **Resolved (2026-09-04) — Stale dossier response guard.** Dossier success and failure paths now capture the active load generation and branch, then discard results after a branch change or reload. A late branch-A response can no longer repopulate branch-B Hotel state or surface a stale error.
10. **Resolved (2026-09-04) — Multi-pet stay binding.** Check-in now selects a stay by membership in the reservation's projected `stayIds` plus its reservation and displayed pet identity; it passes that exact stay to the callable. No independent `pets.first` / `stayIds.first` pairing remains, and ambiguous pet-less multi-stay reservations fail closed.
11. **Resolved (2026-09-04) — Branch-safe read failures.** All four asynchronous operational-read failure paths (stays, care, reservations, and command center) now require both the active load generation and active branch before clearing state or publishing an error.
12. **Resolved (2026-09-04) — Current-detail request guard.** Dossier reads now use a request token and update the presented detail only while that exact stay remains selected. A dismissed or replaced sheet cannot reopen or be overwritten by an earlier response; background care refreshes update the shared list without presenting a sheet.
13. **Recorded (2026-09-04) — Honest parity-verifier limitation.** A hash-bound contract-audit ledger covers check-in, checkout, and `care_operations`. Its compile and verify failures are preserved as verifier limitations caused by delegated outer callables, not converted into product or Infra changes without authorization.
14. **Resolved (2026-09-04) — Accommodation metadata fidelity.** `parseAccommodation` now preserves the authoritative unit `active`, `code`, `allowedSpecies`, and `allowSharedOccupancy` fields. Inactive units no longer appear active, the active-state command inverts the true persisted state, and suite editor prefill retains sharing/species metadata instead of overwriting it with defaults.

## Open findings from final scoped review

No actionable Admin Hotel source findings remain. The final isolated CodeRabbit review (2026-09-04) reviewed the four changed Hotel Swift files and returned zero findings; its earlier diet-confirmation suggestion was correctly dismissed because Infra records that attestation but does not make it a readiness gate. The behavior-ledger verifier remains non-passing because it cannot traverse the reviewed delegated callable architecture; this is recorded as a verification limitation, not a fabricated pass or a reason to weaken production boundaries. Physical-device runtime proof remains unavailable until explicitly approved.

## Remaining work

1. If physical-device validation is explicitly approved, build, install, and launch `PurePetsAdmin.xcworkspace` on a connected iPhone only, using default Xcode DerivedData and never a simulator.
2. Exercise the Hotel route, UIKit back action, permission boundaries, branch switching, check-in, checkout, care, and billing-redaction paths on that approved device; then append actual device evidence here.

## Resume point

All scoped source repairs and static validation are complete. Console and Infra remain read-only references. Await explicit approval before starting any Admin physical-device build/install/launch workflow; do not use a simulator.

## Next authorized runtime step

If physical-device validation is explicitly approved, use `PurePetsAdmin.xcworkspace` and the approved connected iPhone workflow, then verify:

1. Command Center Hotel card appears only for `hotel.view` staff.
2. Card opens the Hotel hub.
3. Back returns through the correct UIKit route in both direct push and app-shell paths.
4. Branch switching cannot show stale Hotel data.
5. Check-in, checkout, room status, care, billing-redaction, and permission-denied states match Console/Infra behavior.
