# Admin Google Sign-In recovery

## Scope and authority

- Target: Admin iOS Google authentication, reported 2026-11-06 as Google Error 400 `invalid_request`, app authenticity / token failure.
- Infra remains authoritative for App Check, Authentication, active `staff_users` authorization, permissions, and audit. No backend contract, roles, claims, or enforcement change is authorized or needed for this client correction.
- Preserve the pre-existing nine-line Debug provider change in `AppManager.m` and unrelated `.trigger-tree/` content.
- Entry skills: Command Center NextGen V1 Admin; Firebase Mission Control V3 for authentication diagnosis.
- Baseline: `4225bba7050cd32e961644f36ff1c6215b83e545`.
- Evidence: `/var/folders/n6/5p16xph116n5w19rfp1yvvxh0000gn/T/pp-admin-google-auth-d298co2u`.

## Phase 1 — Inspect / diagnose: completed

Actual path: `PPProLoginHostingController` -> `PPProLoginCoordinator` -> `FUManager.signInWithGoogle` -> Google OAuth -> Firebase Auth -> existing staff gate. The legacy `AdminLoginViewController` shares the same FUManager call.

Confirmed source defects:

1. Firebase selects Debug App Check for Debug builds; Google always calls production `configureWithCompletion:nil`. Google's App Check client must be configured separately, including its Debug provider.
2. Debug and Release entitlement files omit `com.apple.developer.devicecheck.appattest-environment`. Google requires the `production` App Attest environment.
3. Google setup completion/errors are discarded, login can race setup, and the already-configured Firebase branch skips Google setup.
4. Release can select Debug App Check via environment/default overrides, and the application explicitly logs debug secrets.

Live Firebase registration read: Admin is ACTIVE, with the expected bundle ID and Apple team. OAuth client ID and callback consistency pass the configuration gate. Read-only App Check metadata now confirms that Admin's App Attest configuration is registered (TTL 3600 seconds) and has three debug-token entries. The initial Python transport failed; a system-TLS curl request without an explicit quota project returned 403 `SERVICE_DISABLED`. Repeating the same GET with `x-goog-user-project: pure-pets-49199` succeeded. This was a diagnostic quota-project issue, not proof of an Admin backend outage. No cloud configuration has been changed, and no token value was retrieved or persisted. Metadata counts do not prove the phone's Google Identity token is registered.

References:

- https://developers.google.com/identity/sign-in/ios/appcheck/get-started
- https://developers.google.com/identity/sign-in/ios/appcheck/debug-provider

## Phase 2 — Implementation: completed

- `AppManager.h/.m`: Google App Check preparation owned by the existing singleton. Main-queue callbacks, coalesced setup, 30-second timeout, retry after failure, and generation checks for late/duplicate callbacks. Both Firebase bootstrap branches prepare Google. Debug Google configuration matches the existing Firebase Debug choice; Release cannot enable Debug via runtime overrides. Application-owned debug-secret logs removed.
- `FUManager.m`: both login screens wait for preparation; failure stops OAuth presentation; a dismissed presenter cancels safely. Existing Firebase credential exchange and staff authorization stay in place.
- `PPProLoginCoordinator.m` and `AdminLoginViewController.m`: preserve the localized verification message instead of exposing nested SDK/backend text.
- Debug and Release entitlements: production App Attest environment added; push and Apple sign-in capabilities retained.
- Arabic/English: localized verification recovery and configuration-unavailable copy, through existing `kLang` handling.
- `scripts/verify_google_sign_in_config.py`: configuration gate for matching OAuth IDs/callbacks, canonical project and bundle, both wired entitlement files, signing team, retained capabilities, and paired localization. It does not compile the app or exercise native sign-in.

## Phase 3 — Static verification: completed; device verification pending

- Admin changed-source policy / project membership: PASS.
- SDK declarations for `configureDebugProviderWithAPIKey:completion:`, `configureWithCompletion:`, and cancellation: verified against the installed Google Sign-In SDK.
- `python3 scripts/verify_google_sign_in_config.py`: PASS, 23 checks (OAuth client/callback, canonical project/bundle, both signing configurations and entitlements, preserved push/Apple sign-in, Arabic/English localization).
- Command Center package validator: PASS (tool-package check only).
- Command Center diff-scope validator: PASS, all 11 task files remain in the Admin repository.
- `git diff --check`: PASS.
- Final manual diff review: setup failures cannot enter the Google OAuth call; current and legacy routes share the same guard; late callbacks are generation checked; setup completions are cleared before retry; existing credential exchange and staff gates are preserved. These are source findings, not executed native behavior.
- Physical-device discovery: connected iPhone 13 Pro Max `00008110-00046D640EB8401E` observed on 2026-11-06. This proves connection only.
- App Check metadata: PASS, registered App Attest configuration and three debug-token entries; the actual phone token and OAuth acceptance remain UNVERIFIED.
- Build, signing, install, launch, Google success/cancel/retry on iPhone: UNVERIFIED; no Admin-specific build approval yet. Earlier approval named the consumer service-cell build only.
- No deployment or production mutation performed.

## Next action

Admin-specific build/install approval has been requested for this concrete patch and is pending. Once approved, recheck the connected iPhone 13 Pro Max and use Xcode default DerivedData. Then verify signing accepts the production App Attest entitlement, Google success/cancellation, offline timeout/retry, and unchanged staff authorization. Never claim that building/launching alone proves OAuth success.

For Debug Google verification, the SDK's Google Identity debug token must be registered for Admin; this is independent of Firebase's Debug provider setup. Three entries exist, but the phone's token match has not been verified. No cloud registration or enforcement change has been made. Do not persist tokens in this handoff. If needed, inspect the exact SDK error on device before proposing an authorized configuration change.
