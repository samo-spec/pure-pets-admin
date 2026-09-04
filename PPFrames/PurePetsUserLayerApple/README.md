# PurePetsUserKit

A small, Swift-first current-user layer for Pure Pets. It replaces the mutable `UserModel` God Object with one domain model, one access model, one repository actor, and one main-actor session.

## What ships

- `PPUser`: profile and presentation-neutral user data.
- `PPUserAccess`: verified, fail-closed authorization snapshot.
- `PPRemoteUserRepository`: auth/profile/permission orchestration with stale-operation protection.
- `PPUserSession`: the single source of truth consumed by the app.
- `PPObservableUserSession`: iOS 17 Observation adapter for SwiftUI.
- `PPCurrentUserBridge`: read-only Objective-C/UIKit bridge.
- Firebase adapters for Auth, Firestore, realtime listeners, and protected file cache.
- 16 focused tests and 14 architecture invariants.

## Platform policy

- Core package: iOS 15+, macOS 12+.
- SwiftUI Observation adapter: iOS 17+, macOS 14+.
- Swift 6 language mode and strict concurrency.

## Core rule

```text
Views and controllers
        │
        ▼
PPUserSession (@MainActor)
        │
        ▼
PPUserRepository (protocol)
        │
        ▼
PPRemoteUserRepository (actor)
    ┌───────────┬──────────────┬───────────┐
    ▼           ▼              ▼           ▼
Auth source   User store     User cache   Mapper
```

No screen reads Firebase directly. No screen mutates role, claims, permissions, or restrictions. No cached snapshot grants privileged access.

## Start here

1. Read `Docs/ARCHITECTURE.md`.
2. Follow `Docs/REPOSITORY_INTEGRATION.md`.
3. Use `Docs/MIGRATION_PLAN.md` to replace old call sites incrementally.
4. Run `Tools/verify.sh` before integrating.
5. Validate Firestore Security Rules and real Firebase behavior in the app workspace.

## Local verification

```bash
Tools/verify.sh
```

The script runs formatting, a warnings-as-errors Swift 6 build, 16 tests, integration parsing, Firebase adapter contract type-checking, Objective-C bridge type-checking, and architecture invariants.

## Important boundary

Client authorization is a UI and workflow gate. Firebase Security Rules and trusted backend checks remain authoritative for every protected operation.
