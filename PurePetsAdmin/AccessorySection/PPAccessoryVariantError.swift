//
//  PPAccessoryVariantError.swift
//  PurePetsAdmin
//
//  Typed interpretation of the server's colour-variant error vocabulary.
//
//  The callable returns a stable `domainCode` inside the callable error details
//  alongside a localized message. Branching on the message text is what produced
//  the silent strip-and-retry defect elsewhere in this module, so this layer
//  branches on `domainCode` only and treats an unrecognized code as fatal rather
//  than recoverable.
//
//  Every case carries an explicit recovery intent, so the editor always has a
//  defined next step and never discards the operator's draft on a recoverable
//  failure.
//

import Foundation

/// What the UI should do about a failure.
@objc public enum PPAccessoryVariantRecovery: Int {
    /// The draft is wrong. Keep it, show the message, let the operator fix it.
    case correctInput
    /// Someone else changed the data. Reload from the server, then offer a merge
    /// or a retry. The draft must be preserved for comparison.
    case reloadAndCompare
    /// Transient or unknown transport failure. The same command id may be
    /// retried safely, because the server binds the effect to it.
    case retrySameCommand
    /// The operator lacks permission. No retry will help.
    case permissionDenied
    /// Ordered prerequisite: the public listing must be transferred before the
    /// family change can be accepted.
    case transferPublicListingFirst
    /// Already applied. Treat as success and refresh.
    case treatAsApplied
    /// Not recoverable in this screen.
    case fatal
}

@objc public final class PPAccessoryVariantError: NSObject, @unchecked Sendable {
    @objc public let domainCode: String
    @objc public let message: String
    @objc public let recovery: PPAccessoryVariantRecovery
    /// Product ids the operator must look at, when the server named them.
    @objc public let affectedProductIds: [String]
    /// Populated for a revision conflict so the UI can show both numbers.
    @objc public let expectedRevision: NSNumber?
    @objc public let currentRevision: NSNumber?
    /// True when the draft must be kept. False only for `fatal`.
    @objc public let preservesDraft: Bool

    @objc public init(
        domainCode: String,
        message: String,
        recovery: PPAccessoryVariantRecovery,
        affectedProductIds: [String] = [],
        expectedRevision: NSNumber? = nil,
        currentRevision: NSNumber? = nil
    ) {
        self.domainCode = domainCode
        self.message = message
        self.recovery = recovery
        self.affectedProductIds = affectedProductIds
        self.expectedRevision = expectedRevision
        self.currentRevision = currentRevision
        self.preservesDraft = recovery != .fatal
        super.init()
    }

    // MARK: - Server vocabulary

    /// Exactly the codes `upsertProductVariantFamily` can return. Anything not
    /// listed here is unknown to this client version and is treated as fatal.
    public enum Code {
        public static let unknownFields = "VARIANT_FAMILY_UNKNOWN_FIELDS"
        public static let optionsUnknownFields = "VARIANT_OPTIONS_UNKNOWN_FIELDS"
        public static let contractVersion = "VARIANT_FAMILY_CONTRACT_VERSION_UNSUPPORTED"
        public static let commandConflict = "VARIANT_FAMILY_COMMAND_CONFLICT"
        public static let staleFamilyRevision = "STALE_FAMILY_REVISION"
        public static let staleVariantRevision = "STALE_VARIANT_REVISION"
        public static let familyNotFound = "VARIANT_FAMILY_NOT_FOUND"
        public static let familyArchived = "VARIANT_FAMILY_ARCHIVED"
        public static let duplicateColor = "VARIANT_DUPLICATE_COLOR"
        public static let duplicateProduct = "VARIANT_DUPLICATE_PRODUCT"
        public static let duplicateSku = "VARIANT_DUPLICATE_SKU"
        public static let duplicateBarcode = "VARIANT_DUPLICATE_BARCODE"
        public static let defaultRequired = "VARIANT_DEFAULT_REQUIRED"
        public static let defaultNotSellable = "VARIANT_DEFAULT_NOT_SELLABLE"
        public static let productNotFound = "VARIANT_PRODUCT_NOT_FOUND"
        public static let productDeleted = "VARIANT_PRODUCT_DELETED"
        public static let productClaimed = "VARIANT_PRODUCT_ALREADY_IN_FAMILY"
        public static let kindMismatch = "VARIANT_KIND_TYPE_MISMATCH"
        public static let livePetUnsupported = "VARIANT_LIVE_PET_UNSUPPORTED"
        public static let consumerVisibility = "VARIANT_CONSUMER_VISIBILITY_CONFLICT"
        public static let archivedWithStock = "VARIANT_ARCHIVED_WITH_STOCK"
        public static let selectionIncomplete = "VARIANT_SELECTION_INCOMPLETE"
        public static let duplicateCombination = "VARIANT_DUPLICATE_COMBINATION"
        public static let identityImmutable = "VARIANT_IDENTITY_IMMUTABLE"
        public static let optionReferenceInvalid = "VARIANT_OPTION_REFERENCE_INVALID"
        public static let optionDefinitionsInvalid = "VARIANT_DEFINITIONS_INVALID"
        public static let optionsInvalid = "VARIANT_OPTIONS_INVALID"
        public static let duplicateOption = "VARIANT_DUPLICATE_OPTION"
        public static let duplicateValue = "VARIANT_DUPLICATE_VALUE"
        public static let optionsNotEnabled = "VARIANT_OPTIONS_NOT_ENABLED"
        public static let publicationNotReady = "VARIANT_PUBLICATION_NOT_READY"
        public static let clientUpgradeRequired = "VARIANT_CLIENT_UPGRADE_REQUIRED"
        public static let providerUpgradeRequired = "VARIANT_PROVIDER_UPGRADE_REQUIRED"
        public static let branchLimit = "VARIANT_BRANCH_LIMIT"
        public static let removalRequiresArchive = "VARIANT_REMOVAL_REQUIRES_ARCHIVE"
    }

    // MARK: - Mapping

    /// Interprets an `NSError` produced by the callable.
    ///
    /// `details` is the callable's error details map. A missing `domainCode`
    /// means the failure did not come from the variant contract — most likely
    /// transport — so it maps to a safe same-command retry rather than being
    /// reported as a validation problem the operator cannot act on.
    @objc public static func error(from error: NSError) -> PPAccessoryVariantError {
        let details = (error.userInfo["details"] as? [String: Any])
            ?? (error.userInfo[NSLocalizedFailureReasonErrorKey] as? [String: Any])
            ?? [:]
        let domainCode = (details["domainCode"] as? String) ?? ""
        let productIds = resolveProductIds(from: details)
        let expected = details["expectedRevision"] as? NSNumber
        let current = details["currentRevision"] as? NSNumber

        guard !domainCode.isEmpty else {
            // No domainCode means the failure did not come from the variant
            // contract's validation. Authorization is the important case to
            // separate here: the callable denies with `permission-denied` and no
            // domainCode, and offering a retry for that would be misleading.
            if isPermissionDenied(error) {
                return PPAccessoryVariantError(
                    domainCode: "",
                    message: Language.get(
                        "Variant_Error_PermissionDenied",
                        alter: "لا تملك صلاحية تعديل ألوان هذا المنتج."
                    ),
                    recovery: .permissionDenied
                )
            }
            if isUnauthenticated(error) {
                return PPAccessoryVariantError(
                    domainCode: "",
                    message: Language.get(
                        "Variant_Error_Unauthenticated",
                        alter: "انتهت الجلسة. أعد تسجيل الدخول."
                    ),
                    recovery: .fatal
                )
            }
            return PPAccessoryVariantError(
                domainCode: "",
                message: Language.get(
                    "Variant_Error_Transport",
                    alter: "تعذر إكمال العملية. تحقق من الاتصال وأعد المحاولة."
                ),
                recovery: .retrySameCommand
            )
        }

        let (message, recovery) = describe(
            domainCode: domainCode,
            details: details,
            fallback: error.localizedDescription
        )
        return PPAccessoryVariantError(
            domainCode: domainCode,
            message: message,
            recovery: recovery,
            affectedProductIds: productIds,
            expectedRevision: expected,
            currentRevision: current
        )
    }

    private static func describe(
        domainCode: String,
        details: [String: Any],
        fallback: String
    ) -> (String, PPAccessoryVariantRecovery) {
        switch domainCode {
        case Code.duplicateColor:
            return (
                Language.get("Variant_Error_DuplicateColorServer", alter: "هذا اللون مستخدم بالفعل في هذا المنتج."),
                .correctInput
            )
        case Code.duplicateProduct:
            return (
                Language.get("Variant_Error_DuplicateProductServer", alter: "نفس المنتج مضاف أكثر من مرة."),
                .correctInput
            )
        case Code.duplicateSku:
            return (
                Language.get("Variant_Error_DuplicateSkuServer", alter: "رمز SKU مستخدم بلون آخر. لكل لون رمز خاص."),
                .correctInput
            )
        case Code.duplicateBarcode:
            return (
                Language.get("Variant_Error_DuplicateBarcodeServer", alter: "الباركود مستخدم بلون آخر. لكل لون باركود خاص."),
                .correctInput
            )
        case Code.defaultRequired:
            return (
                Language.get("Variant_Error_DefaultRequiredServer", alter: "يجب تحديد لون افتراضي نشط."),
                .correctInput
            )
        case Code.defaultNotSellable:
            return (
                Language.get("Variant_Error_DefaultArchivedServer", alter: "اللون الافتراضي مؤرشف. اختر لونًا نشطًا أولًا."),
                .correctInput
            )
        case Code.archivedWithStock:
            return (
                Language.get("Variant_Error_ArchivedWithStockServer", alter: "لا يمكن أرشفة لون لا يزال يحتوي على مخزون."),
                .correctInput
            )
        case Code.kindMismatch:
            return (
                Language.get("Variant_Error_KindMismatchServer", alter: "كل ألوان المنتج يجب أن تكون من نفس النوع."),
                .correctInput
            )
        case Code.livePetUnsupported:
            return (
                Language.get("Variant_Error_LivePetServer", alter: "الحيوانات الحية تُتابع فرديًا ولا تدعم الألوان المتعددة."),
                .fatal
            )
        case Code.consumerVisibility:
            // Ordered prerequisite, not a plain validation error: the outgoing
            // default must be unlisted and the incoming default listed before
            // the family can be re-pointed.
            return (
                Language.get(
                    "Variant_Error_ConsumerVisibilityServer",
                    alter: "اللون غير الافتراضي معروض في المتجر. أوقف عرضه ثم اعرض اللون الافتراضي الجديد قبل الحفظ."
                ),
                .transferPublicListingFirst
            )
        case Code.productClaimed:
            return (
                Language.get("Variant_Error_ProductClaimedServer", alter: "هذا المنتج ينتمي بالفعل إلى مجموعة ألوان أخرى."),
                .correctInput
            )
        case Code.productNotFound, Code.productDeleted:
            return (
                Language.get("Variant_Error_ProductMissingServer", alter: "أحد الألوان لم يعد موجودًا. أعد تحميل البيانات."),
                .reloadAndCompare
            )
        case Code.familyNotFound:
            return (
                Language.get("Variant_Error_FamilyMissingServer", alter: "مجموعة الألوان غير موجودة. أعد تحميل البيانات."),
                .reloadAndCompare
            )
        case Code.familyArchived:
            return (
                Language.get("Variant_Error_FamilyArchivedServer", alter: "مجموعة الألوان مؤرشفة ولا يمكن تعديلها."),
                .fatal
            )
        case Code.staleFamilyRevision, Code.staleVariantRevision:
            return (
                Language.get(
                    "Variant_Error_StaleRevisionServer",
                    alter: "عدّل موظف آخر هذا المنتج أثناء تعديلك. أعد التحميل وقارن قبل الحفظ."
                ),
                .reloadAndCompare
            )
        case Code.commandConflict:
            // The key is bound to different content. Treat as applied and
            // refresh: retrying with the same key can never succeed, and a new
            // key would risk duplicating an effect that may already exist.
            return (
                Language.get(
                    "Variant_Error_CommandConflictServer",
                    alter: "تم تنفيذ عملية أخرى بنفس المعرف. أعد التحميل للتحقق من النتيجة."
                ),
                .treatAsApplied
            )
        case Code.unknownFields, Code.optionsUnknownFields, Code.contractVersion:
            // The client sent something this server rejects outright. This is a
            // version mismatch, never something the operator can fix, and it
            // must fail loudly instead of retrying with fields removed.
            let fields = (details["fields"] as? [String])?.joined(separator: ", ") ?? ""
            let base = Language.get(
                "Variant_Error_ContractMismatchServer",
                alter: "إصدار التطبيق غير متوافق مع الخادم. حدّث التطبيق."
            )
            return (fields.isEmpty ? base : "\(base) (\(fields))", .fatal)
        case Code.selectionIncomplete:
            return (
                Language.get(
                    "Variant_Error_SelectionIncomplete",
                    alter: "يجب تحديد قيمة لكل خيار في جميع المتغيرات. انتقل إلى المصفوفة لتعيينها."
                ),
                .correctInput
            )
        case Code.identityImmutable:
            return (
                Language.get("Options_Error_IdentityImmutable", alter: "لا يمكن تغيير قيمة خيار محفوظ لصنف موجود. أنشئ متغيرًا جديدًا للتوليفة الجديدة للحفاظ على المخزون والسجل."),
                .correctInput
            )
        case Code.duplicateCombination:
            return (
                Language.get(
                    "Variant_Error_DuplicateCombinationServer",
                    alter: "توجد توليفة خيارات مكررة بين متغيرين. لكل متغير توليفة فريدة."
                ),
                .correctInput
            )
        case Code.optionReferenceInvalid, Code.optionDefinitionsInvalid, Code.optionsInvalid, Code.duplicateOption, Code.duplicateValue:
            return (
                Language.get(
                    "Variant_Error_OptionInvalidServer",
                    alter: "توجد بيانات غير صالحة في تعريف الخيارات أو قيمها."
                ),
                .correctInput
            )
        case Code.optionsNotEnabled:
            return (
                Language.get(
                    "Variant_Error_OptionsNotEnabledServer",
                    alter: "خيارات المنتجات غير مفعّلة في إعدادات النظام حالياً."
                ),
                .fatal
            )
        case Code.publicationNotReady:
            return (
                Language.get(
                    "Variant_Error_PublicationNotReadyServer",
                    alter: "يجب تفعيل عرض الخيارات للعملاء في النظام قبل نشر هذا الصنف."
                ),
                .fatal
            )
        case Code.clientUpgradeRequired:
            return (
                Language.get(
                    "Variant_Error_ClientUpgradeRequiredServer",
                    alter: "يتطلب هذا الصنف تحديث التطبيق إلى أحدث إصدار."
                ),
                .fatal
            )
        case Code.providerUpgradeRequired:
            return (
                Language.get(
                    "Variant_Error_ProviderUpgradeRequiredServer",
                    alter: "تخصيص الخيارات لمزودي الخدمة يتطلب مساراً متوافقاً."
                ),
                .correctInput
            )
        case Code.branchLimit:
            return (
                Language.get(
                    "Variant_Error_BranchLimitServer",
                    alter: "يتجاوز هذا المنتج الحد المسموح لنطاق الفروع المتاح."
                ),
                .fatal
            )
        case Code.removalRequiresArchive:
            return (
                Language.get(
                    "Variant_Error_RemovalRequiresArchiveServer",
                    alter: "يرجى أرشفة المتغير بدلاً من حذفه مباشرة للحفاظ على سلامة المخزون."
                ),
                .correctInput
            )
        default:
            // Unknown code: fail closed. Never assume a newer server error is
            // benign or retryable.
            return (fallback.isEmpty
                ? Language.get("Variant_Error_Unknown", alter: "تعذر حفظ الألوان.")
                : fallback, .fatal)
        }
    }

    private static func resolveProductIds(from details: [String: Any]) -> [String] {
        if let list = details["productIds"] as? [String] { return list }
        if let single = details["productId"] as? String, !single.isEmpty { return [single] }
        return []
    }

    // Callable error codes, per the Firebase Functions canonical code list.
    // Matched numerically so this file does not need to import FirebaseFunctions
    // and stays a pure domain type.
    private static let functionsErrorDomain = "com.firebase.functions"
    private static let permissionDeniedCode = 7
    private static let unauthenticatedCode = 16

    private static func isPermissionDenied(_ error: NSError) -> Bool {
        error.domain == functionsErrorDomain && error.code == permissionDeniedCode
    }

    private static func isUnauthenticated(_ error: NSError) -> Bool {
        error.domain == functionsErrorDomain && error.code == unauthenticatedCode
    }

    // MARK: - Presentation

    /// Whether the editor may offer a retry button for this failure.
    @objc public var isRetryable: Bool {
        switch recovery {
        case .retrySameCommand, .reloadAndCompare, .transferPublicListingFirst, .correctInput:
            return true
        case .permissionDenied, .treatAsApplied, .fatal:
            return false
        }
    }

    /// Whether the same command id may be reused. Only true when the server
    /// never bound it to a different effect.
    @objc public var allowsSameCommandRetry: Bool {
        recovery == .retrySameCommand
    }
}
