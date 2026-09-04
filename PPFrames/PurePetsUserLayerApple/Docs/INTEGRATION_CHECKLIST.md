# Integration checklist

## Project setup

- [ ] Copy package into the Pure Pets repository.
- [ ] Add it as a local Swift package.
- [ ] Link `PurePetsUserKit` to the app target.
- [ ] Add Firebase, SwiftUI, Objective-C bridge and Pure Pets integration files to the app target.
- [ ] Expose existing permission and collection constants to Swift.
- [ ] Confirm the app deployment target is iOS 15 or newer.

## Composition

- [ ] Construct exactly one `PPUserSession`.
- [ ] Start it at the authenticated app root.
- [ ] Inject `PPObservableUserSession` into iOS 17 SwiftUI screens.
- [ ] Inject one `PPCurrentUserBridge` into Objective-C/UIKit flows.
- [ ] Do not instantiate repositories per screen.

## Migration

- [ ] Replace admin and management gates.
- [ ] Replace posting, selling and chat gates.
- [ ] Replace purchase, withdrawal and partner gates.
- [ ] Replace profile reads.
- [ ] Replace profile writes with `PPUserProfilePatch`.
- [ ] Remove old permission listeners and writes.
- [ ] Remove old cache ownership.
- [ ] Remove mutable authorization mirrors.

## Verification

- [ ] Run `Tools/verify.sh`.
- [ ] Build the real app scheme with warnings as errors.
- [ ] Run all app and package tests on Simulator.
- [ ] Test sign-in, sign-out and token refresh.
- [ ] Test rapid account switching.
- [ ] Test offline cache and reconnect.
- [ ] Test blocked/disabled accounts.
- [ ] Run Firebase Emulator Security Rules tests.
- [ ] Run Instruments for leaks and duplicate listeners.
- [ ] Confirm logs contain no public UID, token, email or claim data.
