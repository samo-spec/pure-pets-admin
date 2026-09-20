from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
ASSISTANT = (ROOT / "PurePetsAdmin/Features/Pury/UI/PuryAssistantSheetView.swift").read_text()

print("Running Pury perimeter safe-area regression test...")

# Pury must have an explicit optical perimeter in addition to the system safe area.
# Internal message/composer padding alone is not enough because the crown surface and
# safe-area inset container otherwise remain visually flush with the device boundary.
assert "private static let sheetPerimeterInset: CGFloat = 8" in ASSISTANT

# The primary foreground canvas must breathe away from the physical left/right edges,
# while the top navbar background extends to fill the top safe area layout guide inset.
assert ".padding(.horizontal, Self.sheetPerimeterInset)" in ASSISTANT
assert ".safeAreaInset(edge: .top, spacing: 0)" in ASSISTANT
assert "puryCommandCrown" in ASSISTANT
assert ".ignoresSafeArea(.all, edges: .top)" in ASSISTANT

CROWN = (ROOT / "PurePetsAdmin/Features/Pury/UI/PuryCommandCrown.swift").read_text()
assert "PPStatusBarHelper.statusBarHeight" in CROWN
assert ".frame(maxWidth: .infinity)" in CROWN

# The bottom command dock lives outside the main VStack via safeAreaInset, so it must
# independently preserve the same optical perimeter above the system bottom safe area.
assert "floatingInputDock\n                .padding(.horizontal, Self.sheetPerimeterInset)\n                .padding(.bottom, Self.sheetPerimeterInset)" in ASSISTANT

# Background atmosphere may remain immersive; only interactive chrome/content is inset.
assert "ambientAtmosphere" in ASSISTANT
assert ".ignoresSafeArea()" in ASSISTANT

print("Pury perimeter safe-area regression test passed.")
