#!/usr/bin/env python3
from pathlib import Path
import sys

root = Path(__file__).resolve().parents[1]
core = root / "Sources" / "PurePetsUserKit"
integration = root / "Integration"

files = {p.relative_to(root).as_posix(): p.read_text() for p in root.rglob("*.swift")}
core_text = "\n".join(p.read_text() for p in core.rglob("*.swift"))

checks = [
    ("Legacy God Object is absent from production sources", "class UserModel" not in core_text and "@interface UserModel" not in core_text),
    ("Core transport contains no Any dictionaries", "[String: Any]" not in core_text),
    ("Access construction is package-scoped", "package init(" in files["Sources/PurePetsUserKit/Access/PPUserAccess.swift"]),
    ("Unknown capability rules fail closed", ".unsupportedCapability" in files["Sources/PurePetsUserKit/Access/PPUserAccess.swift"]),
    ("Canonical chat values guard legacy fallback", "canonicalChatFeatureExists" in files["Sources/PurePetsUserKit/Mapping/PPUserMapper.swift"] and "canonicalChatRestrictionExists" in files["Sources/PurePetsUserKit/Mapping/PPUserMapper.swift"]),
    ("Profile claims never enter access mapping", "profile.ppObject(\"claims\")" not in files["Sources/PurePetsUserKit/Mapping/PPUserMapper.swift"]),
    ("Repository is actor-isolated", "public actor PPRemoteUserRepository" in files["Sources/PurePetsUserKit/Repository/PPRemoteUserRepository.swift"]),
    ("Cross-account generation checks exist", "generation == ticket" in files["Sources/PurePetsUserKit/Repository/PPRemoteUserRepository.swift"]),
    ("Session is MainActor-isolated", "@MainActor\npublic final class PPUserSession" in files["Sources/PurePetsUserKit/Session/PPUserSession.swift"]),
    ("Firebase observes ID-token changes", "addIDTokenDidChangeListener" in files["Integration/Firebase/PPFirebaseAuthSource.swift"]),
    ("Profile writes verify authenticated UID", "auth.currentUser?.uid == userID.rawValue" in files["Integration/Firebase/PPFirebaseUserStore.swift"]),
    ("Cache is downgraded before use", ".cachedCopy()" in files["Integration/Firebase/PPFileUserCache.swift"]),
    ("Objective-C bridge exposes decisions, not mutable permission mirrors", "isAllowed(_ capability" in files["Integration/ObjectiveCBridge/PPCurrentUserBridge.swift"] and "setPermission" not in files["Integration/ObjectiveCBridge/PPCurrentUserBridge.swift"]),
    ("Core files remain bounded below 300 lines", all(len(p.read_text().splitlines()) < 300 for p in core.rglob("*.swift"))),
]

failed = []
for name, passed in checks:
    print(f"{'PASS' if passed else 'FAIL'}: {name}")
    if not passed:
        failed.append(name)

print(f"\n{len(checks) - len(failed)}/{len(checks)} architecture checks passed")
sys.exit(1 if failed else 0)
