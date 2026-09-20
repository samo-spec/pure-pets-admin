from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
AVATAR = (ROOT / "PurePetsAdmin/Features/Pury/UI/PuryAvatar.swift").read_text()
STORE = (ROOT / "PurePetsAdmin/Features/Pury/Conversation/PuryConversationStore.swift").read_text()
CROWN = (ROOT / "PurePetsAdmin/Features/Pury/UI/PuryCommandCrown.swift").read_text()
ASSETS = ROOT / "PurePetsAdmin/Assets.xcassets"

print("Running Pury rendered-motion contract tests...")

for symbol in [
    "enum PuryMotionState",
    "PuryMotionAssetStore",
    "PuryLoopingVideoView",
    "AVPlayerLooper",
    "accessibilityReduceMotion",
]:
    assert symbol in AVATAR, f"missing rendered-motion symbol: {symbol}"

for state in [
    "idle", "thinking", "searching", "responding",
    "success", "confused", "warning", "error",
]:
    assert f"case {state}" in AVATAR, f"missing motion state: {state}"
    dataset = ASSETS / f"PuryMotion{state.title()}.dataset"
    movie = dataset / f"PuryMotion{state.title()}.mp4"
    assert dataset.is_dir(), f"missing data asset: {dataset.name}"
    assert movie.is_file() and movie.stat().st_size > 20_000, f"invalid motion clip: {movie.name}"

assert "var puryMotionState: PuryMotionState" in STORE
for mapping in [
    ".loading: return .thinking",
    ".pending: return .searching",
    ".ready: return .success",
    ".empty: return .confused",
    ".confirmationRequired: return .warning",
    ".conflictStale: return .warning",
    ".denied, .error: return .error",
]:
    assert mapping in STORE, f"missing truthful state mapping: {mapping}"

assert "motionState: state.puryMotionState" in CROWN
assert "isLiving: true" in CROWN
print("Pury rendered-motion contract tests passed.")
