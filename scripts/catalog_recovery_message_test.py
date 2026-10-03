#!/usr/bin/env python3
"""Exercise shipping rejection handling and durable recovery copy without an app build."""
from pathlib import Path
import subprocess, tempfile
root = Path(__file__).resolve().parents[1]
source = (root / "PurePetsAdmin/AccessorySection/PPAccessoryEditorView.swift").read_text()
service = (root / "PurePetsAdmin/AccessorySection/PPInventoryCommandService.swift").read_text()
start = source.index("                    let definitiveRejection = PPInventoryCommandService.isDefinitiveSaveRejection(err)")
end = source.index("                    UINotificationFeedbackGenerator().notificationOccurred(.error)", start)
callback = source[start:end].replace("self.", "")
struct = source[source.index("private struct PPStandardInventoryRecovery:"):source.index("/// Prepared accessory/food image payload")]
struct = struct.replace("private struct", "struct")
fixture = r'''
import Foundation
enum Language { static func get(_ key: String, alter: String) -> String { key + (key.hasSuffix("_Format") ? " %@" : "") } }
struct UINotificationFeedbackGenerator { enum Kind { case warning }; func notificationOccurred(_ kind: Kind) {} }
enum PPInventoryCommandService {
 static func isDefinitiveSaveRejection(_ error: Error) -> Bool { (error as NSError).code == 422 }
 static func staleRevision(from error: Error) -> Int? { nil }
 static func userFacingErrorMessage(for error: Error) -> String { "Update the app, then retry" }
}
final class Editor {
 var hasPendingStandardSave = true
 var standardSaveMayHaveCommitted = false
 var errorMessage: String?
 var persistedFailure: String?
 var clears = 0
 func clearStandardInventoryRecovery() { clears += 1; hasPendingStandardSave = false }
 func persistStandardRecoveryFailure() { if hasPendingStandardSave { persistedFailure = errorMessage } }
 func reject(_ err: Error) { /* CALLBACK */ }
}
/* RECOVERY_STRUCT */
let rejection = NSError(domain: "pp.inventory.command", code: 422)
let fresh = Editor(); fresh.reject(rejection)
precondition(fresh.clears == 1 && !fresh.hasPendingStandardSave && fresh.errorMessage == "Update the app, then retry")
let uncertain = Editor(); uncertain.standardSaveMayHaveCommitted = true; uncertain.reject(rejection)
precondition(uncertain.clears == 0 && uncertain.hasPendingStandardSave && uncertain.persistedFailure?.contains("Update the app") == true)
let timeout = Editor(); timeout.reject(NSError(domain: "com.firebase.functions", code: 4))
precondition(timeout.clears == 0 && timeout.standardSaveMayHaveCommitted && timeout.persistedFailure != nil)
let oldRecord = try JSONSerialization.data(withJSONObject: ["requestData": Data("retained-command".utf8).base64EncodedString(), "oldImageURLs": ["photo"]])
let decoded = try JSONDecoder().decode(PPStandardInventoryRecovery.self, from: oldRecord)
precondition(decoded.failureMessage == nil && decoded.oldImageURLs == ["photo"])
var updated = decoded; updated.failureMessage = "Check access, then recover this save"
let reopened = try JSONDecoder().decode(PPStandardInventoryRecovery.self, from: JSONEncoder().encode(updated))
precondition(reopened.requestData == decoded.requestData && reopened.failureMessage == updated.failureMessage)
print("CATALOG_RECOVERY_MESSAGE_TEST: PASS (fresh rejection unlocks, uncertain rejection retains command, timeout, legacy record, durable reason)")
'''
with tempfile.TemporaryDirectory(prefix="pp-recovery-message-") as temp:
 path = Path(temp) / "Recovery.swift"
 path.write_text(fixture.replace("/* CALLBACK */", callback).replace("/* RECOVERY_STRUCT */", struct))
 subprocess.run(["swift", str(path)], check=True)
