#!/usr/bin/env python3
"""Validate Admin's cross-file OAuth/App Attest configuration without building.

This is a source configuration gate, not device attestation or sign-in proof.
Only pass/fail descriptions are printed; Firebase API keys are never emitted.
"""

import json
from pathlib import Path
import plistlib
import re
import subprocess
import sys


ROOT = Path(__file__).resolve().parents[1]
APP = ROOT / "PurePetsAdmin"


def read_plist(path):
    return plistlib.loads(path.read_bytes())


def main():
    checks = []

    def check(name, passed):
        checks.append({"check": name, "status": "PASS" if passed else "FAIL"})

    info = read_plist(APP / "Info.plist")
    firebase = read_plist(APP / "GoogleService-Info.plist")
    client_id = firebase.get("CLIENT_ID")
    check("Google and Firebase use the same iOS OAuth client", bool(client_id) and info.get("GIDClientID") == client_id)
    schemes = {
        scheme
        for url_type in info.get("CFBundleURLTypes", [])
        for scheme in url_type.get("CFBundleURLSchemes", [])
    }
    check("Google callback scheme is registered", bool(firebase.get("REVERSED_CLIENT_ID")) and firebase["REVERSED_CLIENT_ID"] in schemes)
    check("Firebase configuration belongs to the canonical project", firebase.get("PROJECT_ID") == "pure-pets-49199")
    check("Firebase configuration belongs to Admin", firebase.get("BUNDLE_ID") == "Ali-Ahmed.PurePetsAdmin")

    project = subprocess.run(
        ["plutil", "-convert", "json", "-o", "-", str(ROOT / "PurePetsAdmin.xcodeproj/project.pbxproj")],
        check=True, capture_output=True, text=True,
    )
    objects = json.loads(project.stdout)["objects"]
    target = next(value for value in objects.values() if value.get("isa") == "PBXNativeTarget" and value.get("name") == "PurePetsAdmin")
    configs = objects[target["buildConfigurationList"]]["buildConfigurations"]
    check("Both Debug and Release configurations exist", {objects[key]["name"] for key in configs} == {"Debug", "Release"})
    for key in configs:
        config = objects[key]
        name = config["name"]
        settings = config["buildSettings"]
        check(f"{name}: target uses Admin bundle ID", settings.get("PRODUCT_BUNDLE_IDENTIFIER") == firebase.get("BUNDLE_ID"))
        check(f"{name}: target uses the registered Apple team", settings.get("DEVELOPMENT_TEAM") == "9J4UK6N4AU")
        path = ROOT / settings["CODE_SIGN_ENTITLEMENTS"]
        entitlements = read_plist(path)
        check(f"{name}: wired entitlement uses production App Attest", entitlements.get("com.apple.developer.devicecheck.appattest-environment") == "production")
        check(f"{name}: Apple sign-in capability is preserved", entitlements.get("com.apple.developer.applesignin") == ["Default"])
        check(f"{name}: push environment is preserved", entitlements.get("aps-environment") == ("development" if name == "Debug" else "production"))

    keys = ("auth_google_verification_failed", "auth_google_configuration_error", "StatusNetworkError")
    for language in ("ar", "en"):
        strings_path = APP / f"{language}.lproj" / "Localizable.strings"
        result = subprocess.run(["plutil", "-lint", str(strings_path)], capture_output=True, text=True)
        check(f"{language}: localization file parses", result.returncode == 0)
        strings = strings_path.read_text()
        for key in keys:
            entries = re.findall(r'^\s*"' + re.escape(key) + r'"\s*=\s*"(.+)"\s*;', strings, re.MULTILINE)
            check(f"{language}: {key} exists exactly once", len(entries) == 1)

    print(json.dumps({"evidenceType": "static-configuration", "checks": checks}, indent=2))
    return int(any(item["status"] == "FAIL" for item in checks))


if __name__ == "__main__":
    try:
        sys.exit(main())
    except (OSError, ValueError, KeyError, StopIteration, subprocess.CalledProcessError) as error:
        # Do not dump parsed configuration or SDK values in diagnostic output.
        print(json.dumps({"evidenceType": "static-configuration", "status": "FAIL", "reason": type(error).__name__}))
        sys.exit(1)
