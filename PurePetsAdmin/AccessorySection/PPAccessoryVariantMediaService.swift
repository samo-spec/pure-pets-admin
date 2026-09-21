//
//  PPAccessoryVariantMediaService.swift
//  PurePetsAdmin
//
//  Per-colour media for accessory variants.
//
//  ── Storage layout ─────────────────────────────────────────────────────────
//  Accessory uploads were historically flat — `petAccessories/<UUID>.jpg` — so
//  nothing tied an object to the product, let alone to a colour. Orphan cleanup
//  had to guess extensions, and two colours of one product were
//  indistinguishable in the bucket.
//
//  Variant media uses a deterministic, variant-scoped path:
//
//      petAccessories/{productId}/variants/{colorId}/{uuid}.{ext}
//
//  `storage.rules:700-705` already matches `petAccessories/{allPaths=**}`, so
//  this needs **no rule change and no rule weakening**. It inherits the existing
//  guarantees: `stock.manage`/`stock.create` (or owner metadata match),
//  image-or-video content type, a 20 MB ceiling, and `resource == null` on
//  create so an upload can never overwrite an existing object.
//
//  ── Write ownership ────────────────────────────────────────────────────────
//  Images live on each colour's own `petAccessories` document, so the catalog
//  write goes through `validateInventoryChange` for that exact `productId`. The
//  family callable is never given an image field — that would make it a second
//  writer of catalog media.
//
//  ── Failure discipline ─────────────────────────────────────────────────────
//  Uploads are deferred: picking only stages bytes in memory, and objects are
//  written just before the catalog save. A staged object whose catalog save
//  never lands is deleted, and a retry reuses the already-uploaded URLs rather
//  than uploading a second copy.
//

import Foundation
import UIKit
import FirebaseAuth
import FirebaseStorage

/// One image staged for a specific colour.
struct PPAccessoryVariantStagedImage: Identifiable {
    let id: UUID
    let image: UIImage
    /// Set once Storage confirms the object, so a retry does not re-upload.
    var uploadedURL: String?
    var width: Int
    var height: Int

    init(image: UIImage) {
        self.id = UUID()
        self.image = image
        self.uploadedURL = nil
        self.width = Int(image.size.width.rounded())
        self.height = Int(image.size.height.rounded())
    }
}

/// Result of committing one colour's media.
struct PPAccessoryVariantMediaCommit {
    let productId: String
    let imageURLs: [String]
    let imageMeta: [[String: Any]]
    /// Objects that are no longer referenced and may be deleted after the
    /// catalog write is confirmed.
    let orphanedURLs: [String]
}

enum PPAccessoryVariantMediaError: LocalizedError {
    case notAuthenticated
    case unpreparableImage
    case uploadFailed(underlying: Error)
    case tooManyImages(limit: Int)

    var errorDescription: String? {
        switch self {
        case .notAuthenticated:
            return Language.get("Variant_Media_NotAuthenticated", alter: "يجب تسجيل الدخول لتحميل الصور.")
        case .unpreparableImage:
            return Language.get("Variant_Media_BadImage", alter: "تعذر تجهيز إحدى الصور. اختر صورة أخرى.")
        case .uploadFailed:
            return Language.get("Variant_Media_UploadFailed", alter: "فشل تحميل الصور. تم الاحتفاظ باختيارك، أعد المحاولة.")
        case .tooManyImages(let limit):
            let template = Language.get("Variant_Media_TooMany", alter: "الحد الأقصى %@ صور لكل لون.")
            return String(format: template, NSNumber(value: limit))
        }
    }
}

@MainActor
final class PPAccessoryVariantMediaService {
    static let shared = PPAccessoryVariantMediaService()

    /// Matches the server's `imageURLsArray` ceiling of 12 entries.
    static let maxImagesPerVariant = 12

    private let storage = Storage.storage()

    private init() {}

    // MARK: - Paths

    /// Deterministic, variant-scoped object path.
    ///
    /// Keyed on the colour identifier rather than a name or hex, so renaming or
    /// repainting a colour never orphans its media.
    static func objectPath(
        productId: String,
        colorId: String,
        assetId: UUID,
        fileExtension: String
    ) -> String {
        let safeColor = colorId.isEmpty ? "unassigned" : colorId
        return "petAccessories/\(productId)/variants/\(safeColor)/\(assetId.uuidString).\(fileExtension)"
    }

    // MARK: - Upload

    /// Uploads every staged image that does not yet have a remote URL.
    ///
    /// Mutates `staged` in place so a partial failure keeps the URLs that did
    /// succeed: a retry then uploads only what is still missing instead of
    /// duplicating objects in the bucket.
    func uploadStagedImages(
        _ staged: inout [PPAccessoryVariantStagedImage],
        productId: String,
        colorId: String
    ) async throws {
        guard let uid = Auth.auth().currentUser?.uid else {
            throw PPAccessoryVariantMediaError.notAuthenticated
        }
        guard staged.count <= Self.maxImagesPerVariant else {
            throw PPAccessoryVariantMediaError.tooManyImages(limit: Self.maxImagesPerVariant)
        }

        for index in staged.indices where staged[index].uploadedURL == nil {
            guard let payload = PPAccessoryEditorViewModel
                .prepareAccessoryImageForUpload(staged[index].image) else {
                throw PPAccessoryVariantMediaError.unpreparableImage
            }

            let path = Self.objectPath(
                productId: productId,
                colorId: colorId,
                assetId: staged[index].id,
                fileExtension: payload.fileExtension
            )

            let metadata = StorageMetadata()
            metadata.contentType = payload.contentType
            // Mirrors the existing accessory upload metadata so the Storage
            // owner-match rule keeps working for non-stock staff.
            metadata.customMetadata = [
                "uploaded_by": uid,
                "entity_type": "accessory",
                "media_type": "image",
                "variant_color_id": colorId,
                "product_id": productId,
            ]

            do {
                let reference = storage.reference().child(path)
                try await Self.putData(payload.data, metadata: metadata, at: reference)
                let url = try await Self.downloadURL(for: reference)
                staged[index].uploadedURL = url.absoluteString
                staged[index].width = Int(payload.image.size.width.rounded())
                staged[index].height = Int(payload.image.size.height.rounded())
            } catch {
                throw PPAccessoryVariantMediaError.uploadFailed(underlying: error)
            }
        }
    }

    // Continuation wrappers, matching the pattern already used for accessory and
    // live-pet uploads in this module rather than depending on a newer SDK async
    // surface the project does not otherwise use.
    private static func putData(
        _ data: Data,
        metadata: StorageMetadata,
        at reference: StorageReference
    ) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            reference.putData(data, metadata: metadata) { _, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: ())
                }
            }
        }
    }

    private static func downloadURL(for reference: StorageReference) async throws -> URL {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<URL, Error>) in
            reference.downloadURL { url, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let url {
                    continuation.resume(returning: url)
                } else {
                    continuation.resume(throwing: PPAccessoryVariantMediaError.uploadFailed(
                        underlying: NSError(
                            domain: "pp.variant.media",
                            code: 5,
                            userInfo: [NSLocalizedDescriptionKey: "Missing download URL."]
                        )
                    ))
                }
            }
        }
    }

    /// Builds the catalog payload for one colour.
    ///
    /// Ordering is authoritative: index 0 is the primary image. Legacy consumer
    /// clients read `imageURLsArray.first`, so the primary must stay first for
    /// them to keep rendering the right picture.
    func commit(
        productId: String,
        retainedURLs: [String],
        staged: [PPAccessoryVariantStagedImage],
        previousURLs: [String],
        metadataByURL: [String: [String: Any]]
    ) -> PPAccessoryVariantMediaCommit {
        var urls = retainedURLs
        var meta: [[String: Any]] = retainedURLs.map { url in
            metadataByURL[url] ?? ["url": url]
        }

        for item in staged {
            guard let url = item.uploadedURL, !url.isEmpty else { continue }
            urls.append(url)
            var entry: [String: Any] = ["url": url]
            if item.width > 0 { entry["width"] = item.width }
            if item.height > 0 { entry["height"] = item.height }
            meta.append(entry)
        }

        let keptSet = Set(urls)
        let orphans = previousURLs.filter { !keptSet.contains($0) }

        return PPAccessoryVariantMediaCommit(
            productId: productId,
            imageURLs: urls,
            imageMeta: meta,
            orphanedURLs: orphans
        )
    }

    /// Persists a colour's media through the catalog owner.
    ///
    /// `validateInventoryChange` owns `imageURLsArray` and `imageMeta`, so the
    /// write routes there for the colour's own product id. Nothing about the
    /// family document changes.
    func persist(
        _ commit: PPAccessoryVariantMediaCommit,
        commandId: String,
        expectedRevision: Int?
    ) async throws {
        _ = try await PPLivePetInventoryService.updateCatalogPresentation(
            productID: commit.productId,
            values: [
                "imageURLsArray": commit.imageURLs,
                "imageMeta": commit.imageMeta,
            ],
            commandID: commandId,
            expectedRevision: (expectedRevision ?? 0) > 0 ? expectedRevision : nil
        )
    }

    // MARK: - Cleanup

    /// Deletes objects that the confirmed catalog state no longer references.
    ///
    /// Best effort by design: the catalog document is already correct at this
    /// point, so a failed delete leaves an unreferenced object rather than a
    /// broken product. Never called before the catalog write is confirmed.
    func deleteOrphans(_ urls: [String]) async {
        for url in urls where !url.isEmpty {
            guard let reference = try? storage.reference(forURL: url) else { continue }
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                reference.delete { _ in continuation.resume() }
            }
        }
    }

    /// Removes objects staged for an abandoned edit, so cancelling an upload does
    /// not leak bucket storage.
    func discardStagedUploads(_ staged: [PPAccessoryVariantStagedImage]) async {
        await deleteOrphans(staged.compactMap(\.uploadedURL))
    }
}
