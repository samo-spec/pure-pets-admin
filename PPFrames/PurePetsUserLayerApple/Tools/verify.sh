#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

printf '\n[1/7] Format lint\n'
swift format lint --strict --recursive Sources Tests Integration Examples Tools/VerificationStubs

printf '\n[2/7] Swift 6 core build\n'
swift package clean
swift build -Xswiftc -warnings-as-errors

printf '\n[3/7] Core tests\n'
swift test --parallel -Xswiftc -warnings-as-errors

printf '\n[4/7] Parse every integration source\n'
swiftc -frontend -parse $(find Integration Examples -name '*.swift' -print)

printf '\n[5/7] Firebase adapter contract type-check\n'
STUBS="$(mktemp -d)"
trap 'rm -rf "$STUBS"' EXIT
swiftc -emit-module -module-name FirebaseAuth Tools/VerificationStubs/FirebaseAuth.swift \
  -emit-module-path "$STUBS/FirebaseAuth.swiftmodule"
swiftc -emit-module -module-name FirebaseFirestore Tools/VerificationStubs/FirebaseFirestore.swift \
  -emit-module-path "$STUBS/FirebaseFirestore.swiftmodule"
MODULES=".build/x86_64-unknown-linux-gnu/debug/Modules"
swiftc -typecheck -swift-version 6 -warnings-as-errors -I "$MODULES" -I "$STUBS" \
  Integration/Firebase/PPFirebaseDocumentConverter.swift \
  Integration/Firebase/PPFirebaseAuthSource.swift \
  Integration/Firebase/PPFirebaseUserStore.swift \
  Integration/Firebase/PPFileUserCache.swift \
  Integration/Firebase/PPFirebaseUserLayerAssembly.swift

printf '\n[6/7] SwiftUI and Objective-C bridge type-check\n'
swiftc -typecheck -swift-version 6 -warnings-as-errors -I "$MODULES" \
  Integration/SwiftUI/PPObservableUserSession.swift
swiftc -typecheck -swift-version 6 -warnings-as-errors -I "$MODULES" \
  -Xfrontend -enable-objc-interop Integration/ObjectiveCBridge/PPCurrentUserBridge.swift

printf '\n[7/7] Architecture invariants\n'
python3 Tools/verify_architecture.py

printf '\nAll local verification gates passed.\n'
