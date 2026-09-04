# Apple-grade user layer architecture

## Design intent

The previous user model mixed profile data, Firebase transport, persistence, listeners, authorization, compatibility aliases, and UI helpers. This package replaces that shape with focused types that each have one reason to change.

The architecture follows five invariants:

1. One source of truth for the signed-in user.
2. Profile data and authorization data never share a trust boundary.
3. Every capability is evaluated through one typed, fail-closed policy.
4. Firebase and disk persistence are adapters, not domain concerns.
5. UIKit, Objective-C, and SwiftUI consume the same session state.

## Layers

### Domain

`PPUser` is a `Codable`, `Equatable`, `Sendable` value type. It contains only profile data:

- stable user identifier;
- username, name, email, phone and biography;
- avatar and cover images;
- presence;
- country and reputation;
- creation and update timestamps.

It contains no Firebase APIs, permission dictionaries, storage operations, completion blocks, or controller-oriented state.

### Access

`PPUserAccess` is an immutable access snapshot. Its verified initializer is package-scoped, so application code cannot manufacture trusted access.

It owns:

- trusted token role and admin state;
- account and block state;
- subscription summary;
- granted permission names;
- token expiry and trust state;
- one explicit rule for every supported capability.

Evaluation order is deterministic:

1. verified trust;
2. unexpired token;
3. disabled or blocked account;
4. active account;
5. explicit capability rule.

Missing or unsupported capability rules deny access.

### Transport-neutral documents

`PPDocument` and `PPDocumentValue` isolate Firestore-shaped data from the domain. The core package contains no `[String: Any]` transport dictionaries.

The Firebase converter is the only place that translates SDK values into transport-neutral values.

### Repository

`PPUserRepository` exposes only three operations:

- a stream of current-user events;
- explicit refresh;
- allowlisted profile update.

`PPRemoteUserRepository` is an actor. It owns the current auth generation, token revision, remote stream, cache, and mapping. Generation checks prevent an old user request from publishing after sign-out or account switching.

### Session

`PPUserSession` is `@MainActor` and is the app-facing source of truth. It exposes explicit states:

- `idle`;
- `loading`;
- `signedOut`;
- `ready(snapshot)`;
- `failed(failure, lastSnapshot)`.

The failed state can preserve the last snapshot for continuity without converting cached access into trusted authorization.

### Platform adapters

- `PPObservableUserSession` maps the session into Observation for iOS 17 SwiftUI.
- `PPCurrentUserBridge` exposes a read-only Objective-C interface for UIKit migration.
- `PPFirebaseAuthSource` observes ID-token changes rather than only sign-in changes.
- `PPFirebaseUserStore` owns profile and permission listeners and validates the authenticated UID before writes.
- `PPFileUserCache` provides atomic, protected persistence and always downgrades decoded access to cached.

## Data flow

```text
Firebase Auth ID-token event
             │
             ▼
      PPAuthUser + token claims
             │
Firestore profile + layered permissions
             │
             ▼
        PPUserMapper
             │
             ▼
PPCurrentUserSnapshot(PPUser, PPUserAccess)
             │
             ▼
      PPUserSession.state
       ┌────────┴────────┐
       ▼                 ▼
SwiftUI adapter     Objective-C bridge
```

## Permission precedence

Permission collections are supplied from lowest to highest priority. The final layer wins for every explicit key:

```text
legacy < alternate legacy < canonical
```

An explicit `false` is retained. It is not treated as a missing value and is never replaced by a feature fallback.

Canonical chat values also take precedence over legacy chat fields. Legacy chat values are read only when the canonical feature or restriction field is absent.

## Why this is simpler

The core call-site surface is intentionally small:

```swift
session.state
session.decision(for: .useChat)
try await session.updateProfile(patch)
await session.refresh()
```

Controllers no longer decide how role, feature, restriction, subscription, token expiry, and permissions combine. That logic exists once.

## File-size boundary

Every core source file is kept below 300 lines. Large behavior is split by responsibility rather than hidden in extensions or nested compatibility helpers.
