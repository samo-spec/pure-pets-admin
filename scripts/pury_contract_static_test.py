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
assert "structuredResultHeader" in ASSISTANT
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
assert "purySmartAnswerView(message, structuredContent: structuredContent)" in ASSISTANT
assert '"Pury_Field_CheckIn" = "تسجيل الوصول";' in AR_LOCALIZATION

# Pury command crown: one header surface, language-scoped localization, no raw identifiers.
CROWN = (ROOT / "PurePetsAdmin/Features/Pury/UI/PuryCommandCrown.swift").read_text()

assert "struct PuryCommandCrown" in CROWN
assert "PurySignalSpine" in CROWN
assert "PuryHeaderSignal" in CROWN
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

print("Pury Admin static contract tests passed.")

# Unmapped screens remain inspectable as technical context instead of disappearing.
assert "if let screen = screen, !screen.isEmpty {" in MODELS
assert "value: mapped ?? screen" in MODELS
# Every non-empty route remains inspectable; mapped routes show their localized label.
assert "if let route = route, !route.isEmpty {" in MODELS
assert "value: mapped ?? route" in MODELS
