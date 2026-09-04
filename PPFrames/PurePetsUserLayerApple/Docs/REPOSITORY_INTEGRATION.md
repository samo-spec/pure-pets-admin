# Pure Pets repository integration

The online repository could not be cloned in the current execution environment, so this is delivered as a verified overlay rather than a pushed branch. Integrate it in the real Xcode workspace using the sequence below.

## 1. Add the local package

Copy this folder into the repository, for example:

```text
Packages/PurePetsUserKit/
```

In Xcode, add it as a local Swift package and link `PurePetsUserKit` to the application target.

## 2. Add application adapters

Add these files to the app target, not the package target:

```text
Integration/Firebase/*
Integration/SwiftUI/*
Integration/ObjectiveCBridge/*
Integration/PurePets/*
```

The Firebase adapters require `FirebaseAuth` and `FirebaseFirestore`.

## 3. Expose existing Objective-C constants to Swift

`PPPurePetsUserLayer.swift` intentionally reuses existing project constants:

```text
kPPUsersCol
kPPLegacyPermsSubCol
kPPLegacyPermsSubColAlt
kPPPermsSubCol
kPermPostAds
kPermAdoption
kPermSellNew
```

Ensure the headers defining those constants are present in the bridging header or module imported by the Swift app target.

Add the remaining permission constant names to `PPPermissionCatalog` when they exist in the repository. Do not duplicate them as new string literals in controllers.

## Data readiness

The mapper denies missing account, feature, and permission state. Backfill canonical production data before switching authorization call sites. Do not restore permissive client defaults merely to preserve old behavior.

## 4. Create one session at the composition root

Create the session once in the app composition root, such as the app delegate, scene delegate, coordinator root, or dependency container:

```swift
@MainActor
final class PPAppDependencies {
  let userSession: PPUserSession

  init() throws {
    userSession = try PPPurePetsUserLayer.makeSession()
  }
}
```

Do not create a repository or session per screen.

## 5. SwiftUI integration

For iOS 17 screens:

```swift
@State private var currentUser: PPObservableUserSession

init(session: PPUserSession) {
  _currentUser = State(initialValue: PPObservableUserSession(session: session))
}

var body: some View {
  RootView()
    .environment(currentUser)
    .task { currentUser.start() }
}
```

Views read state and invoke session operations. Business and authorization logic stays out of `body`.

## 6. Objective-C/UIKit integration

Construct one `PPCurrentUserBridge` from the shared session, call `start`, and inject the bridge into legacy coordinators/controllers.

Use:

```objc
BOOL canChat = [bridge isAllowed:PPObjCUserCapabilityUseChat];
```

Do not mirror bridge values into mutable `UserModel` permission properties.

Observe `PPCurrentUserBridge.didChangeNotification` or KVO-compatible read-only properties for legacy UI refreshes.

## 7. Profile writes

Replace dictionaries and direct Firestore updates with `PPUserProfilePatch`. Only profile fields are writable:

- username;
- first and last name;
- phone;
- biography;
- avatar;
- country;
- cover images.

Role, claims, account status, features, restrictions, subscription, and permissions are deliberately absent.

## 8. Build validation in the real workspace

Run:

```text
xcodebuild build
xcodebuild test
```

against the real app scheme and an iOS Simulator. Validate the actual Firebase SDK version, bridging header, deployment target, and project warning policy.

## App Check verification

Project material available to this review contains conflicting App Check configuration: one source describes enforcement while a backend configuration disables it. Resolve that mismatch in the real repository before treating App Check as active. App Check remains abuse resistance and must not replace authorization rules.

## 9. Rules and emulator validation

Before release, test at least these cases against the Firebase Emulator Suite:

- normal user cannot write role, admin, claims, features, restrictions, subscription or permissions;
- a user can update only their own allowlisted profile fields;
- blocked and disabled users cannot perform protected writes;
- canonical permission denial overrides legacy grants;
- admin operations require trusted claims;
- switching accounts cannot expose the previous user's cached or in-flight data.
