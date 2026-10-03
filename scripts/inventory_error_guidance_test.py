#!/usr/bin/env python3
"""Execute shipping inventory error handling against rejection/retry fixtures.

Runs Foundation Swift only; does not build or launch an app or use Firebase.
"""
from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parents[1]
source = (root / "PurePetsAdmin/AccessorySection/PPInventoryCommandService.swift").read_text()
start = source.index("    // MARK: - Inventory failure presentation")
end = source.index("    /// Recognizes optimistic concurrency", start)
helpers = source[start:end].replace("@nonobjc ", "")
start = source.index("    static func unsupportedFieldRejection(")
end = source.index("    private func parseCommandResponse(", start)
wrapper = source[start:end]
start = source.index("    public func readBackProduct(")
end = source.index("\n}\n", start)
readback = source[start:end]

fixture = r'''
import Foundation
let FunctionsErrorDomain = "com.firebase.functions"
enum FunctionsErrorCode: Int {
    case cancelled = 1, unknown = 2, invalidArgument = 3, deadlineExceeded = 4
    case notFound = 5, alreadyExists = 6, permissionDenied = 7, resourceExhausted = 8
    case failedPrecondition = 9, aborted = 10, outOfRange = 11, unimplemented = 12
    case internalError = 13, unavailable = 14, dataLoss = 15, unauthenticated = 16
}
enum Language {
    static func get(_ key: String, alter: String) -> String { key }
}
final class PetAccessory: @unchecked Sendable {
    init(dictionary: [String: Any], documentID: String) {}
}
struct Metadata { var isFromCache = false; var hasPendingWrites = false }
struct Snapshot {
    var exists = true; var metadata = Metadata(); var revision = 3
    func data() -> [String: Any]? { ["revision": revision] }
}
final class FirestoreStub {
    enum Source { case server, cache }
    var snapshot: Snapshot? = Snapshot(); var error: Error?; var requestedSource: Source?
    func collection(_ name: String) -> FirestoreStub { self }
    func document(_ id: String) -> FirestoreStub { self }
    func getDocument(source: Source, completion: (Snapshot?, Error?) -> Void) {
        requestedSource = source; completion(snapshot, error)
    }
}
final class PPInventoryCommandService {
    static let errorDomain = "pp.inventory.command"
    static let unsupportedFieldsErrorCode = 422
    let firestore = FirestoreStub()
    // SHIPPING_HELPERS
    // SHIPPING_WRAPPER
    // SHIPPING_READBACK
}
func callable(_ code: Int, _ domainCode: String? = nil, detailsKey: String = "details") -> NSError {
    var info: [String: Any] = [NSLocalizedDescriptionKey: "RAW_SERVER_OR_SDK_TEXT"]
    if let domainCode { info[detailsKey] = ["domainCode": domainCode, "fields": ["secretTechnicalField"]] }
    return NSError(domain: FunctionsErrorDomain, code: code, userInfo: info)
}
func wrapped(_ error: NSError) -> NSError {
    NSError(domain: "test.wrapper", code: 999,
            userInfo: [NSLocalizedDescriptionKey: "RAW_WRAPPER_TEXT", NSUnderlyingErrorKey: error])
}
func message(_ error: Error) -> String { PPInventoryCommandService.userFacingErrorMessage(for: error) }
for code in [3, 5, 7, 9, 16] {
    precondition(PPInventoryCommandService.isDefinitiveSaveRejection(callable(code)))
    precondition(PPInventoryCommandService.isDefinitiveSaveRejection(wrapped(callable(code))))
}
for code in [1, 2, 4, 6, 8, 10, 11, 12, 13, 14, 15] {
    precondition(!PPInventoryCommandService.isDefinitiveSaveRejection(callable(code)),
                 "Ambiguous or conflict outcome must keep the pending command: \(code)")
    precondition(!PPInventoryCommandService.isDefinitiveSaveRejection(wrapped(callable(code))))
}
let unsupported = callable(3, "INVENTORY_UNKNOWN_FIELDS")
let normalized = PPInventoryCommandService.unsupportedFieldRejection(from: unsupported)!
precondition(normalized.domain == PPInventoryCommandService.errorDomain && normalized.code == 422)
precondition(PPInventoryCommandService.isDefinitiveSaveRejection(normalized),
             "The wrapped definite rejection caused the original pending-save trap")
precondition(normalized.userInfo[NSUnderlyingErrorKey] as? NSError === unsupported)
precondition(normalized.userInfo["fields"] as? [String] == ["secretTechnicalField"])
precondition(message(normalized) == "Inventory_Error_UpdateRequired")
precondition(normalized.localizedDescription == "Inventory_Error_UpdateRequired")
precondition(PPInventoryCommandService.unsupportedFieldRejection(from: callable(14)) == nil)
for detailsKey in ["details", "FIRFunctionsErrorDetailsKey"] {
    for (domainCode, key) in [
        ("BRANCH_ID_REQUIRED", "Inventory_SpecificBranchRequired"),
        ("BRANCH_INACTIVE", "Inventory_Error_BranchUnavailable"),
        ("STALE_REVISION", "Inventory_CatalogChangedReopen"),
        ("INVENTORY_COMMAND_CONFLICT", "Inventory_Error_CommandConflict"),
        ("INVENTORY_LOT_MIGRATION_REQUIRED", "Inventory_Error_TrackingOperation"),
        ("VARIANT_VISIBILITY_REQUIRES_FAMILY_COMMAND", "Inventory_Error_VariantVisibility"),
        ("INVENTORY_DELETE_BLOCKED_BY_STOCK", "Inventory_Error_RemainingStock")
    ] {
        precondition(message(wrapped(callable(9, domainCode, detailsKey: detailsKey))) == key)
    }
}
for (code, key) in [(7, "PermissionDenied"), (16, "SessionExpired"), (3, "InvalidInput"),
                    (9, "Precondition"), (5, "NotFound"), (6, "AlreadyExists"),
                    (8, "Busy"), (14, "Connection"), (4, "Connection"), (13, "Unknown")] {
    precondition(message(wrapped(callable(code))) == "Inventory_Error_\(key)")
}
let network = NSError(domain: NSURLErrorDomain, code: -1009,
                      userInfo: [NSLocalizedDescriptionKey: "RAW_NETWORK_TEXT"])
precondition(message(network) == "Inventory_Error_Connection")
precondition(!PPInventoryCommandService.isDefinitiveSaveRejection(network))
let firestore = NSError(domain: "FIRFirestoreErrorDomain", code: 7)
precondition(message(firestore) == "Inventory_Error_PermissionDenied")
precondition(!PPInventoryCommandService.isDefinitiveSaveRejection(firestore),
             "A readback denial must not clear a potentially committed command")
let future = callable(13, "FUTURE_UNKNOWN_CODE")
precondition(message(future) == "Inventory_Error_Unknown")
precondition(!message(future).contains("RAW") && !message(normalized).contains("secretTechnicalField"))
var deeplyWrapped = future
for _ in 0..<20 { deeplyWrapped = wrapped(deeplyWrapped) }
precondition(message(deeplyWrapped) == "Inventory_Error_Unknown")
precondition(!PPInventoryCommandService.isDefinitiveSaveRejection(deeplyWrapped))
for (raw, key) in [
    ("name is too long.", "Inventory_Error_Name"),
    ("nameEn is too long.", "Inventory_Error_Name"),
    ("sku is too long.", "Inventory_Error_SKU"),
    ("barcode is too long.", "Inventory_Error_Barcode"),
    ("price must be within range and have at most two decimal places.", "CatalogIntake_ValidationPrice"),
    ("costPrice must be a monetary number.", "CatalogIntake_ValidationCost"),
    ("quantity must be an integer.", "Inventory_Error_Quantity"),
    ("petMainCategoryIDs[0] must be an integer.", "Inventory_Error_Category"),
    ("quantityGroup \"pack\" requires a localized name.", "Inventory_Error_SellingUnits"),
    ("Duplicate barcode across quantity groups: abc", "Inventory_Error_SellingUnits"),
    ("imageURLsArray[0] is invalid.", "Inventory_Error_Images")
] {
    let invalid = NSError(domain: FunctionsErrorDomain, code: 3,
                          userInfo: [NSLocalizedDescriptionKey: raw])
    precondition(message(invalid) == key, "Legacy field guidance missing: \(raw)")
    precondition(PPInventoryCommandService.isDefinitiveSaveRejection(invalid))
}
let unknownField = NSError(domain: FunctionsErrorDomain, code: 3,
                          userInfo: [NSLocalizedDescriptionKey: "nameOfFutureField must be valid."])
precondition(message(unknownField) == "Inventory_Error_InvalidInput")
let transportWithValidationText = NSError(domain: FunctionsErrorDomain, code: 14,
                                        userInfo: [NSLocalizedDescriptionKey: "name is too long."])
precondition(message(transportWithValidationText) == "Inventory_Error_Connection")
precondition(!PPInventoryCommandService.isDefinitiveSaveRejection(transportWithValidationText))
final class ReadbackBox: @unchecked Sendable {
    var product: PetAccessory?; var error: Error?
}
for (snapshot, shouldConfirm) in [
    (Snapshot(metadata: Metadata(), revision: 3), true),
    (Snapshot(metadata: Metadata(), revision: 2), false),
    (Snapshot(metadata: Metadata(isFromCache: true), revision: 3), false),
    (Snapshot(metadata: Metadata(hasPendingWrites: true), revision: 3), false),
    (Snapshot(exists: false), false)
] {
    let service = PPInventoryCommandService(); let result = ReadbackBox()
    service.firestore.snapshot = snapshot
    service.readBackProduct(productId: "product", minimumRevision: 3) { product, error in
        result.product = product; result.error = error
    }
    precondition(service.firestore.requestedSource == .server)
    precondition((result.product != nil) == shouldConfirm)
    precondition((result.error == nil) == shouldConfirm)
}
print("INVENTORY_ERROR_GUIDANCE_TEST: PASS (wrapped rejection, ambiguous recovery, typed and legacy field messages, auth, server-only readback, safe fallback, bounded unwrapping)")
'''
with tempfile.TemporaryDirectory(prefix="pp-inventory-guidance-") as temp:
    script = Path(temp) / "InventoryErrorGuidance.swift"
    script.write_text(fixture.replace("    // SHIPPING_HELPERS", helpers)
                     .replace("    // SHIPPING_WRAPPER", wrapper)
                     .replace("    // SHIPPING_READBACK", readback))
    subprocess.run(["swift", str(script)], check=True)
