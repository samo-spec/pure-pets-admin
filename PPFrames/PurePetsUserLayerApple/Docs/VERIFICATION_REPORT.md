# Verification report

## Scope

Verified targets:

- all core package sources;
- all unit tests;
- Firebase adapters against strict Swift 6 verification stubs;
- SwiftUI Observation adapter;
- Objective-C bridge with Objective-C interoperability enabled;
- architectural invariants.

## Environment

- Swift compiler: 6.2.1 on Linux.
- Swift language mode: 6.
- Apple SDK, Xcode, `xcrun`, iOS Simulator and real Firebase frameworks were unavailable.

## Commands

```bash
Tools/verify.sh
```

The script executed seven gates:

1. strict recursive `swift format` lint;
2. clean Swift 6 build with warnings as errors;
3. 16 unit tests with warnings as errors;
4. parse of every integration and example Swift source;
5. Firebase adapter contract type-check using verification-only stubs;
6. SwiftUI and Objective-C bridge type-check;
7. 14 architecture invariants.

## Results

| Gate | Result |
|---|---|
| Format lint | Pass |
| Swift 6 core build | Pass |
| Unit tests | 16/16 pass |
| Integration parse | Pass |
| Firebase adapter contract | Pass |
| SwiftUI adapter | Pass |
| Objective-C bridge | Pass |
| Architecture invariants | 14/14 pass |

## Tested behavior

The test suite proves:

- unknown, cached and expired access deny;
- every supported capability has an explicit rule;
- canonical chat denial wins over legacy allow;
- legacy chat is used only when canonical fields are missing;
- root-level legacy block remains deny-only;
- explicit permission false wins over feature fallback;
- profile claims cannot grant privileged role;
- Auth identity overrides weaker profile identity;
- verified snapshots combine token, profile and permissions;
- ID-token events refresh claims for the same user;
- stale cross-account token work cannot publish;
- sign-out clears the session;
- the main-actor session publishes one source of truth and forwards decisions.

## Architecture invariants

The static verifier checks:

- no production `UserModel` God Object;
- no `Any` dictionaries in core transport;
- verified access construction is package-scoped;
- missing capability rules fail closed;
- canonical chat guards legacy fallback;
- profile claims never enter access mapping;
- repository actor isolation;
- cross-account generation checks;
- main-actor session isolation;
- Firebase ID-token observation;
- authenticated UID enforcement for writes;
- cache trust downgrade;
- decision-based Objective-C bridge without mutable permission mirrors;
- every core source file remains below 300 lines.

## Limitations

The following remain mandatory in the real repository:

- Xcode build against the actual app deployment target;
- XCTest on an iOS Simulator;
- compilation against the repository's actual Firebase SDK version;
- bridging-header validation;
- Firebase Emulator Security Rules tests;
- end-to-end sign-in, token refresh, account switching and offline tests;
- performance and memory verification in Instruments.

CodeRabbit CLI was not available in the execution environment. No CodeRabbit-generated result is claimed.
