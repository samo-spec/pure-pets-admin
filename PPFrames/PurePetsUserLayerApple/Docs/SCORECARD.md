# Architecture scorecard

## Design score: 96/100

| Area | Weight | Score | Evidence |
|---|---:|---:|---|
| Domain boundaries | 15 | 15 | Focused value types; Firebase absent from core domain |
| Trust and authorization | 20 | 20 | Package-scoped verified construction; fail-closed capability decisions |
| Concurrency and lifecycle | 15 | 15 | Actor repository; MainActor session; generation and token revision checks |
| Persistence | 10 | 9 | Atomic protected cache; forced trust downgrade; no multi-version migration yet |
| API clarity | 10 | 10 | Four-operation app surface; typed profile patch and failures |
| UIKit/SwiftUI interoperability | 10 | 9 | Shared session, Observation adapter and read-only Objective-C bridge; repository call sites not yet migrated |
| Testability | 10 | 9 | Protocol-injected core and 16 tests; real Firebase emulator tests remain |
| Operability and diagnostics | 5 | 4 | Typed failure codes and explicit states; production telemetry integration remains |
| Migration safety | 5 | 5 | Incremental strangler plan without two authoritative paths |
| **Total** | **100** | **96** | |

## Release-readiness score: 88/100

The architecture is ready for repository integration. Production release readiness is lower because the real Pure Pets workspace, current Firebase SDK, Security Rules, simulator flows, and all legacy callers were not executable in this environment.

## Conditions for 98–100

- integrate into the actual repository and remove duplicated user ownership;
- complete caller migration from mutable `UserModel` authorization fields;
- pass Xcode warnings-as-errors build and simulator tests;
- pass Firebase Emulator Security Rules tests;
- validate token revocation, offline recovery and rapid account switching end to end;
- run Instruments for listener lifecycle, memory retention and launch/cache cost;
- add privacy-safe production telemetry for state and failure codes.
