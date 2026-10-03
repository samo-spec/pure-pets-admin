#!/usr/bin/env python3
"""Run shipping cancellation/media/retry methods against an ambiguous save."""
from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parents[1]
source = (root / "PurePetsAdmin/AccessorySection/PPAccessoryEditorView.swift").read_text()

def method(start, end):
    return source[source.index(start):source.index(end, source.index(start))]

methods = [
    method("    func leavePendingStandardSave()", "    private var preventsExplicitDismissal:"),
    method("    func discardPendingStandardSave()", "    private func commitSavedAccessory("),
    method("    func discardChangesAndDismiss()", "    private func cleanupPendingPickedUploads()"),
    method("    func removeExistingImage(at", "    func livePetUnitPhoto(for"),
    method("    func saveAccessory()", "        if isLivePet, let recovery = livePetRecovery") + "    }\n",
]

fixture = r'''
import Foundation
enum Language { static func get(_ key: String, alter: String) -> String { key } }
struct UIImpactFeedbackGenerator {
 enum Style { case medium }; init(style: Style) {}
 func impactOccurred() {}
}
final class Storage {
 static let shared = Storage(); var deletions = 0
 static func storage() -> Storage { shared }
 func reference() -> Storage { self }
 func reference(forURL: String) throws -> Storage { self }
 func child(_ path: String) -> Storage { self }
 func delete(completion: (Error?) -> Void) { deletions += 1; completion(nil) }
}
final class Editor {
 var isSubmitting = false; var hasCompletedSave = false; var isLivePet = false
 var hasPendingStandardSave = true; var standardSaveMayHaveCommitted = true
 var pendingSavedAccessoryDraft: String? = "retained-product"
 var pendingStandardRequest: [String: String]? = ["commandId": "stable-command"]
 var pendingStandardOldImageURLs = ["old-photo"]
 var errorMessage: String?; var commerceLoadError: String?
 var existingImageURLs = ["committed-photo"]; var existingImageMetadata = [["url": "committed-photo"]]
 var pickedImages = [1]; var pickedImageUploadIDs = [UUID()]
 var pendingUnsavedUploads = ["committed-photo": UUID()]
 var clears = 0; var cleanupCalls = 0; var dismissals = 0; var sentCommands: [String] = []
 func clearStandardInventoryRecovery() { clears += 1; hasPendingStandardSave = false; pendingStandardRequest = nil }
 func cleanupPendingPickedUploads() { cleanupCalls += 1 }
 func clearLivePetRecovery() {}
 func onDismiss() { dismissals += 1 }
 func loadCommerceIfAvailable() {}
 func finalizeAccessorySave(accessory: String, oldImageURLs: [String]) {
   sentCommands.append(pendingStandardRequest!["commandId"]!)
 }
 // SHIPPING_METHODS
}

let discard = Editor(); discard.discardPendingStandardSave()
precondition(discard.hasPendingStandardSave && discard.clears == 0,
 "Discarding an ambiguous save must preserve its command identity")
let back = Editor(); back.discardChangesAndDismiss()
precondition(back.hasPendingStandardSave && back.clears == 0 && back.cleanupCalls == 0 && back.dismissals == 0,
 "Back/discard must not erase recovery or delete possibly committed images")
let media = Editor(); media.removeExistingImage(at: 0); media.removePickedImage(at: 0)
precondition(media.existingImageURLs == ["committed-photo"] && media.pickedImages == [1] && Storage.shared.deletions == 0,
 "Pending save media must stay immutable")
let corrupted = Editor(); corrupted.pendingSavedAccessoryDraft = nil; corrupted.pendingStandardRequest = nil
corrupted.saveAccessory()
precondition(corrupted.hasPendingStandardSave && corrupted.clears == 0 && corrupted.sentCommands.isEmpty && corrupted.errorMessage != nil,
 "Unreadable recovery must stay blocked, never restart as a new creation")
let retry = Editor(); retry.saveAccessory(); retry.saveAccessory()
precondition(retry.sentCommands == ["stable-command"] && retry.clears == 0,
 "Retry must send the retained command once and suppress a duplicate tap")
let unsaved = Editor(); unsaved.hasPendingStandardSave = false; unsaved.standardSaveMayHaveCommitted = false
unsaved.discardChangesAndDismiss()
precondition(unsaved.dismissals == 1 && unsaved.cleanupCalls == 1,
 "Ordinary unsaved cancellation remains available")
let leave = Editor(); leave.leavePendingStandardSave()
precondition(leave.dismissals == 1 && leave.clears == 0 && leave.cleanupCalls == 0 && leave.hasPendingStandardSave,
 "Returning to inventory must keep the command and possibly committed media")
let sending = Editor(); sending.isSubmitting = true; sending.leavePendingStandardSave()
precondition(sending.dismissals == 0, "Leaving during send is not allowed")
print("CATALOG_PENDING_SAVE_TEST: PASS (discard, back, media, unreadable recovery, stable retry, duplicate tap, ordinary cancellation)")
'''
with tempfile.TemporaryDirectory(prefix="pp-pending-save-") as temporary:
    path = Path(temporary) / "Pending.swift"
    path.write_text(fixture.replace(" // SHIPPING_METHODS", "\n".join(methods)))
    subprocess.run(["swift", str(path)], check=True)
