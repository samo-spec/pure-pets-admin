import XCTest
@testable import PurePetsAdmin

/// Regression coverage for the reported defect: one Pury answer rendering the same records
/// through three different components (prose, cards, data blocks).
final class PuryAnswerProjectionTests: XCTestCase {

    // MARK: Helpers

    private func metadata(
        cards: [PuryCard]? = nil,
        blocks: [PuryDataBlock]? = nil,
        error: String? = nil,
        resultCount: Int? = nil,
        operation: String? = nil,
        permissionRequired: String? = nil
    ) -> PuryResponseMetadata {
        PuryResponseMetadata(
            operation: operation,
            permissionRequired: permissionRequired,
            structuredData: PuryStructuredData(cards: cards, dataBlocks: blocks),
            result_count: resultCount,
            error: error
        )
    }

    private func stockBlock(id: String, name: String, quantity: String, price: String = "200", visible: String = "true") -> PuryDataBlock {
        PuryDataBlock(
            id: id,
            type: "record",
            collection: "petAccessories",
            fields: [
                PuryField(label: "name", value: name),
                PuryField(label: "Available quantity", value: quantity),
                PuryField(label: "price", value: price),
                PuryField(label: "Final price", value: price),
                PuryField(label: "Visible in app", value: visible)
            ]
        )
    }

    // MARK: The reported duplication

    func testCardAndDataBlockForSameEntityCollapseIntoOneRecord() {
        // The backend described one product twice: once as a title-only card, once as a
        // full data block. Previously both rendered, so the product appeared twice.
        let meta = metadata(
            cards: [PuryCard(id: "c1", title: "هولد", entityType: "petAccessories", entityId: "prod-1")],
            blocks: [stockBlock(id: "prod-1", name: "هولد", quantity: "85")]
        )

        let records = PuryAnswerProjection.records(for: meta)

        XCTAssertEqual(records.count, 1, "card and block describing the same entity must merge")
        XCTAssertEqual(records.first?.title, "هولد")
        XCTAssertEqual(records.first?.quantity, 85, "the block's fields must survive the merge")
    }

    func testTitleOnlyCardsDoNotProduceExtraRecordsAlongsideTheirBlocks() {
        // Five title-only cards plus five matching blocks previously rendered as five empty
        // boxes followed by five full cards.
        let names = ["هولد", "كوكتيل", "كوكي", "كنيور", "كاسكو"]
        let cards = names.enumerated().map { index, name in
            PuryCard(id: "c\(index)", title: name, entityId: "prod-\(index)")
        }
        let blocks = names.enumerated().map { index, name in
            stockBlock(id: "prod-\(index)", name: name, quantity: "\(index)")
        }

        let records = PuryAnswerProjection.records(for: metadata(cards: cards, blocks: blocks))

        XCTAssertEqual(records.count, names.count, "merged set must equal the real entity count")
    }

    func testEntitiesWithoutIdsMergeOnNormalizedTitle() {
        let meta = metadata(
            cards: [PuryCard(title: "كوكي")],
            blocks: [stockBlock(id: "block-only", name: "كوكي", quantity: "4")]
        )

        let records = PuryAnswerProjection.records(for: meta)
        XCTAssertEqual(records.count, 1)
        XCTAssertEqual(records.first?.quantity, 4, "the field-bearing block must replace the title-only placeholder")
    }

    func testTitleOnlyRecordDoesNotAdvertiseAnEmptyDisclosure() {
        let record = PuryRecordProjection(
            id: "title-only",
            title: "هولد",
            subtitle: nil,
            status: nil,
            badge: nil,
            entityType: nil,
            entityId: nil,
            collection: nil,
            fields: [],
            actionRoute: nil
        )

        XCTAssertFalse(record.hasDisclosure)
        XCTAssertFalse(record.canOpenRecord)
    }

    func testDistinctEntitiesAreNotMerged() {
        let meta = metadata(
            blocks: [
                stockBlock(id: "a", name: "كوكي", quantity: "4"),
                stockBlock(id: "b", name: "كنيور", quantity: "2")
            ]
        )

        XCTAssertEqual(PuryAnswerProjection.records(for: meta).count, 2)
    }

    func testEmptyCardWithNoTitleAndNoFieldsIsDropped() {
        let meta = metadata(cards: [PuryCard(title: "   ")])
        XCTAssertTrue(PuryAnswerProjection.records(for: meta).isEmpty)
    }

    func testTechnicalFieldsAreStrippedFromRecords() {
        let block = PuryDataBlock(
            id: "x",
            type: "record",
            collection: "petAccessories",
            fields: [
                PuryField(label: "name", value: "كوكي"),
                PuryField(label: "docId", value: "abc123"),
                PuryField(label: "isDeleted", value: "false"),
                PuryField(label: "Available quantity", value: "4")
            ]
        )

        let record = PuryAnswerProjection.records(for: metadata(blocks: [block])).first
        let labels = record?.fields.map { PuryFieldSemantics.key($0.cleanLabel) } ?? []

        XCTAssertFalse(labels.contains("docid"))
        XCTAssertFalse(labels.contains("isdeleted"))
        XCTAssertTrue(labels.contains("availablequantity"))
    }

    // MARK: Narrative disposition

    func testRecordsSuppressProseEnumeration() {
        XCTAssertEqual(PuryAnswerProjection.disposition(recordCount: 10), .advisoryOnly)
    }

    func testProseIsTheAnswerWhenThereAreNoRecords() {
        XCTAssertEqual(PuryAnswerProjection.disposition(recordCount: 0), .full)
    }

    // MARK: Form resolution — exactly one viewer

    func testStockShapeResolvesToLedger() {
        let blocks = (0..<4).map { stockBlock(id: "p\($0)", name: "item\($0)", quantity: "\($0)") }
        let records = PuryAnswerProjection.records(for: metadata(blocks: blocks))
        let form = PuryAnswerProjection.form(metadata: metadata(blocks: blocks), records: records, hasNarrative: true)

        guard case .stockLedger(let ledger) = form else {
            return XCTFail("expected stock ledger, got \(form)")
        }
        XCTAssertEqual(ledger.count, 4)
    }

    func testSingleRecordResolvesToDossier() {
        let blocks = [stockBlock(id: "p1", name: "كوكي", quantity: "4")]
        let records = PuryAnswerProjection.records(for: metadata(blocks: blocks))
        let form = PuryAnswerProjection.form(metadata: metadata(blocks: blocks), records: records, hasNarrative: false)

        guard case .dossier = form else {
            return XCTFail("expected dossier, got \(form)")
        }
    }

    func testNonStockCollectionResolvesToRoster() {
        let blocks = (0..<3).map { index in
            PuryDataBlock(
                id: "u\(index)",
                type: "record",
                collection: "UsersCol",
                fields: [
                    PuryField(label: "name", value: "عميل \(index)"),
                    PuryField(label: "phone", value: "3000000\(index)")
                ]
            )
        }
        let meta = metadata(blocks: blocks)
        let form = PuryAnswerProjection.form(
            metadata: meta,
            records: PuryAnswerProjection.records(for: meta),
            hasNarrative: false
        )

        guard case .roster = form else {
            return XCTFail("expected roster, got \(form)")
        }
    }

    func testPermissionDenialResolvesToExceptionNotProse() {
        let meta = metadata(error: "permission_denied", permissionRequired: "inventory.write")
        let form = PuryAnswerProjection.form(metadata: meta, records: [], hasNarrative: true)

        guard case .exception(.denied) = form else {
            return XCTFail("expected denied exception, got \(form)")
        }
    }

    func testStaleConflictResolvesToStaleException() {
        let form = PuryAnswerProjection.form(metadata: metadata(error: "conflict_stale"), records: [], hasNarrative: true)
        guard case .exception(.stale) = form else {
            return XCTFail("expected stale exception, got \(form)")
        }
    }

    func testZeroResultsWithoutProseResolvesToEmptyVerdict() {
        let form = PuryAnswerProjection.form(metadata: metadata(resultCount: 0), records: [], hasNarrative: false)
        guard case .emptyVerdict = form else {
            return XCTFail("expected empty verdict, got \(form)")
        }
    }

    func testProseOnlyAnswerResolvesToAdvisory() {
        let form = PuryAnswerProjection.form(metadata: metadata(), records: [], hasNarrative: true)
        guard case .advisory = form else {
            return XCTFail("expected advisory, got \(form)")
        }
    }

    // MARK: Stock risk

    func testStockRiskBoundaries() {
        XCTAssertEqual(PuryStockRisk.classify(quantity: 0), .depleted)
        XCTAssertEqual(PuryStockRisk.classify(quantity: 1), .critical)
        XCTAssertEqual(PuryStockRisk.classify(quantity: 3), .critical)
        XCTAssertEqual(PuryStockRisk.classify(quantity: 4), .low)
        XCTAssertEqual(PuryStockRisk.classify(quantity: 10), .low)
        XCTAssertEqual(PuryStockRisk.classify(quantity: 11), .healthy)
        XCTAssertEqual(PuryStockRisk.classify(quantity: nil), .healthy)
    }

    // MARK: Field semantics — no raw backend keys, no wrong-language leakage

    func testRawBackendLabelsAreLocalizedInBothLanguages() {
        XCTAssertEqual(PuryFieldSemantics.label("Final price", language: "ar"), "السعر النهائي")
        XCTAssertEqual(PuryFieldSemantics.label("Final price", language: "en"), "Final price")
        XCTAssertEqual(PuryFieldSemantics.label("Visible in app", language: "ar"), "الظهور في التطبيق")
        XCTAssertEqual(PuryFieldSemantics.label("collection", language: "ar"), "المجموعة")
        XCTAssertEqual(PuryFieldSemantics.label("English name", language: "ar"), "الاسم بالإنجليزية")
    }

    func testBooleanValuesBecomeWordsInTheAnswerLanguage() {
        XCTAssertEqual(PuryFieldSemantics.value("true", label: "Visible in app", language: "ar"), "مفعل")
        XCTAssertEqual(PuryFieldSemantics.value("false", label: "Visible in app", language: "ar"), "معطل")
        XCTAssertEqual(PuryFieldSemantics.value("true", label: "Visible in app", language: "en"), "On")
        XCTAssertEqual(PuryFieldSemantics.value("false", label: "Visible in app", language: "en"), "Off")
    }

    func testCollectionIdentifiersBecomeNames() {
        XCTAssertEqual(PuryFieldSemantics.value("petAccessories", label: "collection", language: "ar"), "مستلزمات وأغذية")
        XCTAssertEqual(PuryFieldSemantics.value("petAccessories", label: "collection", language: "en"), "Accessories & food")
    }

    func testFieldKindDetection() {
        XCTAssertEqual(PuryFieldSemantics.kind(label: "Available quantity", value: "85"), .quantity)
        XCTAssertEqual(PuryFieldSemantics.kind(label: "Final price", value: "200"), .currency)
        XCTAssertEqual(PuryFieldSemantics.kind(label: "Visible in app", value: "true"), .boolean)
        XCTAssertEqual(PuryFieldSemantics.kind(label: "collection", value: "petAccessories"), .identifier)
        XCTAssertEqual(PuryFieldSemantics.kind(label: "English name", value: "Coca"), .text)
    }

    // MARK: Pury-scoped localization must not fall back to the other language

    func testMissingKeyFallsBackWithinTheRequestedLanguage() {
        let arabic = PuryLocale.text("Pury_Key_That_Does_Not_Exist", language: "ar", ar: "عربي", en: "English")
        let english = PuryLocale.text("Pury_Key_That_Does_Not_Exist", language: "en", ar: "عربي", en: "English")
        XCTAssertEqual(arabic, "عربي")
        XCTAssertEqual(english, "English")
    }

    func testShippedContextKeysResolveInBothLanguages() {
        XCTAssertEqual(PuryLocale.text("Pury_Context_Command", language: "en", ar: "؟", en: "؟"), "Command Center")
        XCTAssertEqual(PuryLocale.text("Pury_Context_Command", language: "ar", ar: "؟", en: "؟"), "مركز العمليات والقيادة")
    }

    func testStayContextLabelSubstitutesTheIdentifierInsteadOfPrintingAFormatToken() {
        let context = PuryScreenContext(stayId: "abcdef123456")
        let arabic = context.displayLabel(language: "ar")
        let english = context.displayLabel(language: "en")

        XCTAssertFalse(arabic.contains("%@"), "format token leaked into the Arabic label")
        XCTAssertFalse(english.contains("%@"), "format token leaked into the English label")
        XCTAssertTrue(arabic.contains("abcdef12"))
    }

    func testUnmappedRouteNeverLeaksARawIdentifierAsATitle() {
        let context = PuryScreenContext(screen: "someInternalRouteName", route: "someInternalRouteName")
        XCTAssertEqual(context.displayLabel(language: "en"), "Admin Console")
        XCTAssertFalse(context.displayLabel(language: "ar").contains("someInternalRouteName"))
    }
}
