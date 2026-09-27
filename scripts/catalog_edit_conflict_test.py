#!/usr/bin/env python3
"""Exercise the shipping save callback with a scripted callable transport."""
from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parents[1]
service = (root / "PurePetsAdmin/AccessorySection/PPInventoryCommandService.swift").read_text()
editor = (root / "PurePetsAdmin/AccessorySection/PPAccessoryEditorView.swift").read_text()
start = service.index("    public func executeProductSave(")
end = service.index("    /// Domain for client-side", start)
method = service[start:end]
assert "retryOnStaleRevision" not in method
assert "accessory.map { max(1, $0.revision) }" in editor
assert "expectedRevision: catalogEditRevision" in editor
assert "accessory.revision = stale.current" not in editor
assert "editingAccessory?.revision = stale.current" not in editor
assert "isUpdate ? max(1, accessory.revision) : nil" in service

fixture = r'''
import Foundation
struct PPSendableRequest: @unchecked Sendable { let data: [String: Any] }
final class PPInventoryCommandResult: @unchecked Sendable {}
enum Language { static func get(_ key: String, alter: String) -> String { key } }
final class Transport: @unchecked Sendable {
    var calls: [[String: Any]] = []
    var error: Error?
    func httpsCallable(_ name: String) -> Transport {
        precondition(name == "validateInventoryChange"); return self
    }
    func call(_ data: [String: Any], completion: @escaping (Any?, Error?) -> Void) {
        calls.append(data); completion(nil, error)
    }
}
final class PPInventoryCommandService: @unchecked Sendable {
    let functions = Transport()
    static func unsupportedFieldRejection(from error: Error) -> Error? { nil }
    func parseCommandResponse(result: Any?, commandId: String, productId: String, action: String,
                              completion: @escaping @Sendable (PPInventoryCommandResult?, Error?) -> Void) {
        fatalError("A failed save must not report success")
    }
    // SHIPPING_METHOD
}
final class ResultBox: @unchecked Sendable { var errors: [NSError] = [] }
let service = PPInventoryCommandService()
let results = ResultBox()
let request: [String: Any] = ["action": "update", "commandId": "retained-command", "productId": "food",
                            "expectedRevision": 7, "payload": ["name": "Old draft"]]
for code in [9, 4, 14] {
    service.functions.error = NSError(domain: "com.firebase.functions", code: code,
        userInfo: ["details": ["domainCode": "STALE_REVISION", "currentRevision": 8, "expectedRevision": 7]])
    service.executeProductSave(request: request) { result, error in
        precondition(result == nil)
        results.errors.append(error! as NSError)
    }
}
precondition(service.functions.calls.count == 3, "Implicit retry can overwrite another editor")
precondition(results.errors.map(\.code) == [9, 4, 14], "Errors must reach the editor exactly once")
for call in service.functions.calls {
    precondition(call["commandId"] as? String == "retained-command")
    precondition(call["expectedRevision"] as? Int == 7)
}
print("CATALOG_EDIT_CONFLICT_TEST: PASS (shipping callback: stale/timeout/unavailable; stable envelope; frozen legacy baseline)")
'''
with tempfile.TemporaryDirectory(prefix="pp-catalog-conflict-") as temp:
    script = Path(temp) / "CatalogConflict.swift"
    script.write_text(fixture.replace("    // SHIPPING_METHOD", method))
    subprocess.run(["swift", str(script)], check=True)
