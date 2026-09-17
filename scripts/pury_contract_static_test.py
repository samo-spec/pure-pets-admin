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

print("Pury Admin static contract tests passed.")
