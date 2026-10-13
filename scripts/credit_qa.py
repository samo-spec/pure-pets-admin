#!/usr/bin/env python3
"""Build the separately identified local fixture app on the approved physical iPhone."""
import argparse
import ipaddress
import json
import plistlib
import subprocess
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
DEVICE = "00008110-00046D640EB8401E"
BUNDLE = "Ali-Ahmed.PurePetsAdmin.CreditQA"


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--host", required=True, help="Private IPv4 address of the Mac running the isolated emulators")
    parser.add_argument("--actor", choices=["seller", "denied", "foreign", "disabled"], default="seller")
    parser.add_argument("--build", action="store_true", help="Run only the approved physical-device Debug build")
    args = parser.parse_args()
    address = ipaddress.IPv4Address(args.host)
    if not any(address in ipaddress.ip_network(network) for network in ["10.0.0.0/8", "172.16.0.0/12", "192.168.0.0/16"]):
        parser.error("A private IPv4 host is required; localhost on an iPhone is not this Mac")
    staging = Path(tempfile.mkdtemp(prefix="purepets-credit-qa-build-"))
    info = plistlib.loads((ROOT / "PurePetsAdmin/Info.plist").read_bytes())
    for key in ["CFBundleURLTypes", "GIDClientID", "PPNotificationsEnvironment"]:
        info.pop(key, None)
    info.update({
        "PPLocalCreditEmulatorHost": args.host, "PPLocalCreditProject": "demo-pure-pets-credit", "PPLocalCreditActor": args.actor,
        "FirebaseMessagingAutoInitEnabled": False, "FIREBASE_ANALYTICS_COLLECTION_DEACTIVATED": True,
        "FirebaseCrashlyticsCollectionEnabled": False, "FirebaseAppDelegateProxyEnabled": False,
        "NSAppTransportSecurity": {"NSAllowsArbitraryLoads": True},
        "NSLocalNetworkUsageDescription": "الاتصال بمحاكيات الاختبار المحلية على جهاز Mac. Connect to the local test emulators on this Mac.",
    })
    info_path = staging / "Info.plist"
    info_path.write_bytes(plistlib.dumps(info))
    entitlements = staging / "CreditQA.entitlements"
    entitlements.write_bytes(plistlib.dumps({}))
    command = [
        "xcodebuild", "-workspace", "PurePetsAdmin.xcworkspace", "-scheme", "PurePetsAdmin", "-configuration", "Debug",
        "-destination", f"platform=iOS,id={DEVICE}", "build",
        f"PRODUCT_BUNDLE_IDENTIFIER={BUNDLE}", "INFOPLIST_KEY_CFBundleDisplayName=Pets Credit QA",
        f"INFOPLIST_FILE={info_path}", f"CODE_SIGN_ENTITLEMENTS={entitlements}",
        "GCC_PREPROCESSOR_DEFINITIONS=$(inherited) DEBUG=1 PP_LOCAL_CREDIT_QA=1",
    ]
    receipt = {"device": DEVICE, "bundle": BUNDLE, "project": "demo-pure-pets-credit", "host": args.host,
        "actor": args.actor, "derivedData": "Xcode default", "command": command, "appCheck": "fail-closed; no local attestation"}
    (staging / "build.json").write_text(json.dumps(receipt, indent=2) + "\n")
    print(json.dumps({"buildSetup": str(staging), "bundle": BUNDLE, "buildRequested": args.build}), flush=True)
    if args.build:
        log = staging / "build.log"
        with log.open("w") as stream:
            result = subprocess.run(command, cwd=ROOT, stdout=stream, stderr=subprocess.STDOUT)
        receipt["exitCode"] = result.returncode
        receipt["buildSucceeded"] = result.returncode == 0 and "** BUILD SUCCEEDED **" in log.read_text()
        (staging / "build.json").write_text(json.dumps(receipt, indent=2) + "\n")
        print(json.dumps({"buildSucceeded": receipt["buildSucceeded"], "exitCode": result.returncode, "log": str(log)}))
        raise SystemExit(result.returncode)


if __name__ == "__main__":
    main()
