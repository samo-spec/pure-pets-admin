from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MODELS = (ROOT / "PurePetsAdmin/Features/Pury/Models/PuryModels.swift").read_text()
SERVICE = (ROOT / "PurePetsAdmin/Features/Pury/Service/PuryAdminService.swift").read_text()
ASSISTANT = (ROOT / "PurePetsAdmin/Features/Pury/UI/PuryAssistantSheetView.swift").read_text()
CARD = (ROOT / "PurePetsAdmin/Features/Pury/UI/PuryActionConfirmationCard.swift").read_text()
AUTHOR = (ROOT / "PurePetsAdmin/Features/Pury/Editor/PuryInlineAuthoringHelper.swift").read_text()

print("Running Pury Admin static contract tests...")

assert "enum PuryJSONValue" in MODELS
assert "updates: [String: PuryJSONValue]?" in MODELS
assert "beforeState: [String: PuryJSONValue]?" in MODELS
assert "scope: PuryJSONValue?" in MODELS
assert "expectedRevision" in MODELS
assert "expiresAt" in MODELS
assert "policyVersion" in MODELS

assert "chatTimeoutInterval" in SERVICE
assert "125.0" in SERVICE or "130.0" in SERVICE
assert "PuryJSONValue(any:" in SERVICE
# The server's structured-response cards use `id` / `kind`; legacy producers use
# `entityId` / `entityType`. The client must preserve both before projection merges them.
assert "suppliedCardIdentifier" in SERVICE
assert 'cardDict["kind"] as? String' in SERVICE
assert "?? suppliedCardIdentifier" in SERVICE

assert "PuryActionConfirmationCard(" in ASSISTANT
assert "tactileConfirmationCard(" not in ASSISTANT
assert "parsed.products" not in ASSISTANT
assert "parsed.tables" not in ASSISTANT
assert "parsed.telemetryItems" not in ASSISTANT

assert "errorMessage" in AUTHOR
assert "accessibility" in AUTHOR
assert "action.expectedRevision" in CARD
assert "action.scope" in CARD
assert "accessibilityLabel" in CARD
assert "accessibilityHint" in CARD
CONVERSATION = (ROOT / "PurePetsAdmin/Features/Pury/Conversation/PuryConversationStore.swift").read_text()
assert "commandState" in MODELS
assert "requestId" in MODELS
assert "commandState:" in SERVICE
assert "requestId:" in SERVICE
assert "case pending(String)" in CONVERSATION
assert "receipt_finalize_pending" in CONVERSATION
assert "in_progress" in CONVERSATION

AVATAR = (ROOT / "PurePetsAdmin/Features/Pury/UI/PuryAvatar.swift").read_text()
SHELL = (ROOT / "PurePetsAdmin/App/AdminAppShell.swift").read_text()

# Pury visual/presentation redesign contract.
assert "enum PuryBrand" in AVATAR
assert "PuryBrand.primary" in AVATAR
assert "PuryResponseDisplaySanitizer" in ASSISTANT
assert "cleanNarrative" in ASSISTANT
assert "safeAreaInset(edge: .bottom" in ASSISTANT
assert "safeAreaInset(edge: .top" in ASSISTANT
assert "navigationSafeAreaClearance" in ASSISTANT
assert "answerToNextQueryBreathingRoom" in ASSISTANT
# The result section header moved into each answer viewer, where it belongs to the single
# resolved form rather than sitting above a stack of components.
assert "struct PuryAnswerSectionHeader" in (ROOT / "PurePetsAdmin/Features/Pury/UI/PuryAnswerStudio.swift").read_text()
assert "structuredResultTitle(" in ASSISTANT
assert "PuryBrand.primary" in SHELL
assert "PuryBrand.glow" in SHELL

# Premium records expose human labels rather than raw backend field keys.
assert 'case "petname"' in ASSISTANT
assert 'case "ownername"' in ASSISTANT
assert 'case "checkin", "checkindate", "check_in"' in ASSISTANT
assert "humanizedFallbackLabel" in ASSISTANT
assert "accessibilityReduceMotion" in ASSISTANT

AR_LOCALIZATION = (ROOT / "PurePetsAdmin/ar.lproj/Localizable.strings").read_text()
EN_LOCALIZATION = (ROOT / "PurePetsAdmin/en.lproj/Localizable.strings").read_text()
for key in [
    "Pury_Structured_Results_Subtitle",
    "Pury_Results_ActiveStays_Format",
    "Pury_Record_HotelStay",
    "Pury_Field_Pet",
    "Pury_Field_Owner",
]:
    assert f'"{key}"' in AR_LOCALIZATION
    assert f'"{key}"' in EN_LOCALIZATION


# Copy and visible rendering must share one sanitized structured-data source.
assert "renderableStructuredContent(for: message)" in ASSISTANT
assert "purySmartAnswerView(message, structuredContent: structuredContent, narrativeBlocks: narrativeBlocks)" in ASSISTANT
assert '"Pury_Field_CheckIn" = "تسجيل الوصول";' in AR_LOCALIZATION

# Pury command crown: one header surface, language-scoped localization, no raw identifiers.
CROWN = (ROOT / "PurePetsAdmin/Features/Pury/UI/PuryCommandCrown.swift").read_text()

assert "struct PuryCommandCrown" in CROWN
assert "PurySignalSpine" in CROWN
assert "PuryHeaderSignal" in CROWN
assert "navigationButtonSide: CGFloat = 36" in CROWN
assert "navigationItemHeight: CGFloat = 36" in CROWN
# The crown replaces both legacy bars; neither may come back.
assert "executiveHeaderBar" not in ASSISTANT
assert "contextIndicatorStrip" not in ASSISTANT
assert "headerStatusSubtitle" not in ASSISTANT
assert "puryCommandCrown" in ASSISTANT
# Header strings must resolve through Pury's own language, never app-language `Language.get`.
assert "PuryLocale.text(" in CROWN
assert "enum PuryLocale" in MODELS
assert "public func displayLabel(language:" in MODELS
assert "public func scopeFacets(language:" in MODELS
# An unmapped screen/route must never leak a raw internal identifier as a title.
assert "default:\n            return nil" in MODELS
# Format-bearing context keys must be substituted, not rendered with a literal %@.
assert "PuryLocale.format(" in MODELS
# RTL correctness: backend identifiers stay left-to-right inside Arabic layout.
assert "layoutDirection, .leftToRight" in CROWN
# Size-class safety: no UIScreen-based positioning in the Pury sheet.
assert "UIScreen.main.bounds" not in ASSISTANT
# Reduce Motion must degrade the signal sweep to a static state, not drop the state.
assert "allowsMotion" in CROWN
# Destructive clear is confirmed, not one-tap.
assert "confirmationDialog" in ASSISTANT

for key in [
    "Pury_Context_Command",
    "Pury_Context_Work",
    "Pury_Context_Operations",
    "Pury_Context_People",
    "Pury_Context_Hotel",
    "Pury_Context_POS",
    "Pury_Context_Fulfillment",
    "Pury_Context_More",
    "Pury_Context_Accessories",
    "Pury_Context_LivePets",
    "Pury_Context_Food",
    "Pury_Context_Users",
    "Pury_Context_Staff",
    "Pury_Context_Branches",
    "Pury_Context_Orders",
    "Pury_Name",
    "Pury_Badge_AI",
    "Pury_Close",
    "Pury_Identity_A11y",
    "Pury_State_Ready",
    "Pury_State_Reading",
    "Pury_State_Executing",
    "Pury_State_Awaiting_Approval",
    "Pury_State_Stale",
    "Pury_State_Denied",
    "Pury_State_Alert",
    "Pury_State_NoResults",
    "Pury_Scope_A11y_Label",
    "Pury_Scope_A11y_Hint",
    "Pury_Scope_Screen",
    "Pury_Scope_Route",
    "Pury_Scope_Branch",
    "Pury_Scope_RecordType",
    "Pury_Scope_Record",
    "Pury_Scope_Reservation",
    "Pury_Scope_Stay",
    "Pury_Scope_Suite",
    "Pury_Scope_Authority",
    "Pury_Language_A11y_Label",
    "Pury_Language_Arabic",
    "Pury_Language_English",
    "Pury_Clear_Confirm_Message",
    "Pury_Clear_Confirm_Action",
    "Pury_Clear_Cancel_Action",
]:
    assert f'"{key}"' in AR_LOCALIZATION, f"missing Arabic key: {key}"
    assert f'"{key}"' in EN_LOCALIZATION, f"missing English key: {key}"

# Pury conversation ledger: scope-derived launch deck, earned provenance, real composer.
LEDGER = (ROOT / "PurePetsAdmin/Features/Pury/UI/PuryConversationLedger.swift").read_text()

for symbol in [
    "struct PuryLaunchDeck",
    "enum PuryLaunchDeckComposer",
    "struct PuryQueryTurn",
    "struct PuryAnswerTurnHeader",
    "struct PuryAnswerTurnFooter",
    "struct PuryReadingDossier",
    "struct PuryPendingApprovalRail",
    "struct PuryTactilePressStyle",
    "enum PuryClock",
]:
    assert symbol in LEDGER, f"missing ledger component: {symbol}"

# The legacy composition must not return.
for removed in [
    "livingEmptyStateView",
    "operationalCatalystPod",
    "quickTelemetryTray",
    "quickTelemetryChip",
    "thinkingBubble",
    "userMessageBubble",
    "puryMessageBubble",
    "livingAvatarBeacon",
]:
    assert removed not in ASSISTANT, f"legacy chat composition still present: {removed}"

assert "PuryLaunchDeck(" in ASSISTANT
assert "PuryReadingDossier(" in ASSISTANT
assert "PuryQueryTurn(" in ASSISTANT
assert "puryAnswerTurn(" in ASSISTANT

# The launch deck must consume the context prompts the repository already ships, so the
# deck differs by the screen the operator came from.
for prompt_key in ["Pury_Prompt_ContextStay", "Pury_Prompt_ContextOrder", "Pury_Prompt_ContextProduct"]:
    assert prompt_key in LEDGER, f"scoped prompt not wired: {prompt_key}"
assert "domainPriority" in LEDGER
assert "isScoped" in LEDGER

# Provenance is conditional, never stamped on every turn.
assert "let recordCount: Int? = structuredContent.hasResults" in ASSISTANT
assert "recordCount: Int?" in LEDGER

# Re-running a query and reaching a pending approval are real, wired actions.
assert "rerunQuery(" in ASSISTANT
assert "pendingApprovalAnchor" in ASSISTANT
assert "PuryPendingApprovalRail(language:" in ASSISTANT

# Long answers are read from their beginning.
assert "anchor: last.role == .user ? .bottom : .top" in ASSISTANT

# Localization: no operator-facing string on this surface may resolve against the
# app-wide bundle, and no glyph may be mirrored by hand.
assert "Language.get" not in ASSISTANT, "app-language lookup leaked back into the Pury sheet"
assert "Language.get" not in LEDGER
assert "chevron.left" not in ASSISTANT, "manual RTL glyph mirroring reintroduced"
assert "chevron.right" not in ASSISTANT
assert "PuryLocale.text(" in ASSISTANT
assert "PuryLocale.format(" in ASSISTANT

for key in [
    "Pury_Greeting_Morning",
    "Pury_Greeting_Afternoon",
    "Pury_Greeting_Evening",
    "Pury_Greeting_Night",
    "Pury_Launch_Mission",
    "Pury_Launch_Section_Start",
    "Pury_Launch_Section_Quick",
    "Pury_Launch_Bound_Badge",
    "Pury_Launch_Pod_A11y_Hint",
    "Pury_Launch_ThisStay_Title",
    "Pury_Launch_ThisOrder_Title",
    "Pury_Launch_ThisItem_Title",
    "Pury_Launch_Kicker_Hotel",
    "Pury_Launch_Hotel_Title",
    "Pury_Launch_Stock_Title",
    "Pury_Launch_Orders_Title",
    "Pury_Launch_Kpi_Title",
    "Pury_Quick_Vets_Title",
    "Pury_Quick_Adoption_Title",
    "Pury_Quick_Guests_Title",
    "Pury_Quick_Audit_Title",
    "Pury_Turn_Copy",
    "Pury_Turn_Rerun",
    "Pury_Turn_Records_Format",
    "Pury_Turn_Latency_A11y_Format",
    "Pury_Pending_Approval_Title",
    "Pury_Pending_Approval_Action",
    "Pury_Composer_Clear",
    "Pury_Composer_Send",
    "Pury_CTA_Hotel",
    "Pury_CTA_Order",
    "Pury_CTA_Product",
    "Pury_Stock_Out",
    "Pury_Stock_Low",
    "Pury_Stock_In",
    "Pury_Stock_Units_Format",
    "Pury_Record_ShowLess",
    "Pury_Record_ShowMore_Format",
    "Pury_Record_Generic",
    "Pury_Currency_QAR_Format",
    "Pury_Metric_Vets_Title",
    "Pury_Metric_Branches_Sub",
]:
    assert f'"{key}"' in AR_LOCALIZATION, f"missing Arabic key: {key}"
    assert f'"{key}"' in EN_LOCALIZATION, f"missing English key: {key}"

# Unified Pury answer composition: no duplicated prose + rows, semantic native hierarchy.
assert "enum PuryNarrativeRole" in ASSISTANT
assert "struct PuryNarrativeBlock" in ASSISTANT
assert "nonRedundantNarrativeBlocks" in ASSISTANT
assert "structuredEvidenceTokens" in ASSISTANT
assert "semanticNarrativeView" in ASSISTANT
assert "assistantNarrativeView(displayText, supporting: true)" not in ASSISTANT

# Pury answer studio: one answer, one viewer. The reported defect was the same records
# rendering as prose, then as title-only cards, then as full record cards.
STUDIO = (ROOT / "PurePetsAdmin/Features/Pury/UI/PuryAnswerStudio.swift").read_text()
PROJECTION_TESTS = (ROOT / "PurePetsAdminTests/PuryAnswerProjectionTests.swift").read_text()

for symbol in [
    "enum PuryAnswerProjection",
    "enum PuryAnswerForm",
    "enum PuryFieldSemantics",
    "enum PuryStockRisk",
    "struct PuryRecordProjection",
    "struct PuryStockLedgerView",
    "struct PuryRecordRosterView",
    "struct PuryRecordDossierView",
    "struct PuryMetricBoardView",
    "struct PuryExceptionPanel",
    "struct PuryEmptyVerdictView",
]:
    assert symbol in STUDIO, f"missing answer-studio component: {symbol}"

# Cards and data blocks must be merged on entity identity, never stacked.
assert "func records(for metadata: PuryResponseMetadata?) -> [PuryRecordProjection]" in STUDIO
assert "identityKey(" in STUDIO
assert "func absorb(" in STUDIO

# The orchestrator resolves to exactly one form and switches once.
assert "let form = PuryAnswerProjection.form(" in ASSISTANT
assert "case .stockLedger(let records):" in ASSISTANT
assert "case .dossier(let record):" in ASSISTANT
assert "case .exception(let kind):" in ASSISTANT
assert "case .emptyVerdict:" in ASSISTANT
assert "case .roster(let records):" in ASSISTANT
assert "case .metricBoard(let records):" in ASSISTANT

# The legacy stacked composition must not return.
assert "ForEach(validCards) { card in" not in ASSISTANT, "card stack rendered alongside blocks again"
assert "PuryRecordCardView(block: block" not in ASSISTANT, "record blocks rendered as a second stack again"
assert "structuredContent.cards.count + structuredContent.blocks.count" not in ASSISTANT, \
    "record badge counted card+block duplicates again"

# Prose enumeration never survives next to the records it enumerates.
assert "if block.role == .bullet { return false }" in ASSISTANT

# Raw backend field keys must not reach an Arabic surface untranslated.
for raw_key in ["finalprice", "visibleinapp", "englishname", "collection"]:
    assert f'case "{raw_key}"' in STUDIO or f'"{raw_key}"' in STUDIO, f"unhandled backend field key: {raw_key}"
assert "Pury_Field_FinalPrice" in STUDIO
assert "Pury_Field_VisibleInApp" in STUDIO
assert "var hasDisclosure: Bool" in STUDIO
assert "var canOpenRecord: Bool" in STUDIO

# Numerals and identifiers stay left-to-right inside Arabic layout.
assert "layoutDirection, .leftToRight" in STUDIO
assert "monospacedDigit()" in STUDIO

# Launch-deck offers are gated by real route authorization, not a fixed list.
assert "authorizedIntentIDs" in ASSISTANT and "authorizedIntentIDs" in LEDGER
assert "route.isAuthorized(for: session)" in ASSISTANT

# The regression suite exists and covers the merge, the forms, and the localization.
for case in [
    "testCardAndDataBlockForSameEntityCollapseIntoOneRecord",
    "testTitleOnlyCardsDoNotProduceExtraRecordsAlongsideTheirBlocks",
    "testStockShapeResolvesToLedger",
    "testSingleRecordResolvesToDossier",
    "testPermissionDenialResolvesToExceptionNotProse",
    "testRawBackendLabelsAreLocalizedInBothLanguages",
    "testMissingKeyFallsBackWithinTheRequestedLanguage",
]:
    assert case in PROJECTION_TESTS, f"missing regression test: {case}"

for key in [
    "Pury_Field_FinalPrice",
    "Pury_Field_VisibleInApp",
    "Pury_Field_Collection",
    "Pury_Field_EnglishName",
    "Pury_Value_On",
    "Pury_Value_Off",
    "Pury_Collection_PetAccessories",
    "Pury_Stock_Risk_Depleted",
    "Pury_Stock_Risk_Critical",
    "Pury_Stock_Risk_Low",
    "Pury_Stock_Risk_Healthy",
    "Pury_Stock_Hidden",
    "Pury_Stock_Unit",
    "Pury_Answer_Stock_Title",
    "Pury_Answer_Manage_Inventory",
    "Pury_Answer_Open_Record",
    "Pury_Answer_Empty_Title",
    "Pury_Answer_Broaden",
    "Pury_Exception_Denied_Title",
    "Pury_Exception_Denied_Guidance",
    "Pury_Exception_Stale_Title",
    "Pury_Exception_Failed_Title",
    "Pury_Exception_Required_Permission",
    "Pury_Quick_Delivery_Title",
    "Pury_Quick_Delivery_Prompt",
    "Pury_Quick_Bookings_Title",
    "Pury_Quick_Bookings_Prompt",
    "Pury_Quick_Branches_Title",
    "Pury_Quick_Branches_Prompt",
    "Pury_Quick_Missing_Title",
    "Pury_Quick_Missing_Prompt",
    "Pury_Quick_POS_Title",
    "Pury_Quick_POS_Prompt",
    "Pury_Quick_LivePets_Title",
    "Pury_Quick_LivePets_Prompt",
]:
    assert f'"{key}"' in AR_LOCALIZATION, f"missing Arabic key: {key}"
    assert f'"{key}"' in EN_LOCALIZATION, f"missing English key: {key}"

LEDGER = (ROOT / "PurePetsAdmin/Features/Pury/UI/PuryConversationLedger.swift").read_text()
for query_id in ["vets", "adoption", "guests", "audit", "delivery", "bookings", "branches", "missing", "posSales", "livePets"]:
    assert f'id: "{query_id}"' in LEDGER, f"missing quick query in ledger: {query_id}"
    assert f'"{query_id}"' in ASSISTANT, f"missing quick query authorization: {query_id}"

print("Pury Admin static contract tests passed.")
# Unmapped screens remain inspectable as technical context instead of disappearing.
assert "if let screen = screen, !screen.isEmpty {" in MODELS
assert "value: mapped ?? screen" in MODELS
# Every non-empty route remains inspectable; mapped routes show their localized label.
assert "if let route = route, !route.isEmpty {" in MODELS
assert "value: mapped ?? route" in MODELS
