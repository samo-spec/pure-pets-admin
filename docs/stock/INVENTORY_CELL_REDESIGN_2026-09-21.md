# Inventory product cell redesign — 2026-09-21

Status: implemented; static validation passed. Native build, rendered UI, assistive-technology behavior, and device performance are **UNVERIFIED**. This is not a production-readiness certificate for the Inventory or POS domain.

## Scope and ownership

- Screenshot owner: `PurePetsAdmin/AccessorySection/PPInventoryListView.swift` in Admin iOS. Accessories, food, and live pets now use one `FlagshipInventoryCard` within the established SwiftUI island and UIKit navigation.
- Starting Admin HEAD: `79f84a05c89bd5443ada00b6a453053b5ebeeddb`; starting Infra HEAD: `0f4123422f8da3322cd6aafd62f599960056c6f6`. Both working trees were initially clean.
- Other inventory variant and branch-commerce edits appeared during this task. They are preserved. The complete current diff contains other work; this handoff describes only the cell redesign and its confirmation integration.
- This task changes no Firebase rules, callable payloads, collection identities, server writes, or POS transaction logic. Infra remains the contract authority.

## Design decision

The chosen composition puts the full product name first, then pairs its price and descriptive metadata with a portrait at logical trailing. Availability and its actions occupy one inset operational panel. This separates opening the product from editing its balance, avoids duplicate quantity controls, and leaves full width for longer names.

Alternatives considered were a large photographic card and a dense single-line operational row. The former used too much list space; the latter compressed names, metadata, and touch targets. The implemented composition adapts to available width and expands vertically at accessibility text sizes.

## Changed implementation

| Owner | Change |
|---|---|
| `AccessorySection/PPInventoryListView.swift` | Shared product cell, compact/wide/accessibility compositions, metadata and control wrapping, localized names, state captions, VoiceOver semantics, native buttons, scoped permissions, keypad snapshot checks, and published pending state. |
| `BranchSection/PPBranchInventory.swift` | Existing server readback accepts an optional minimum revision and completion callback. Existing callers remain source-compatible. Cancellation, errors, invalid records, and stale revisions complete explicitly. |
| `ar.lproj/Localizable.strings` / `en.lproj/Localizable.strings` | Paired `InventoryCell_*` copy for availability, loading, unconfirmed/missing data, read-only/inactive states, quantity editing, tracking, and accessibility. |

No Xcode project registration or dependency changes are needed. The shared `CategorySpecimenAuraTheme`, `AdminRemoteImage`, fonts, surface tokens, and `CatalogPressStyle` remain the owners of their respective concerns.

## Behavior and safety

- A selected branch uses its own `availableQuantity` and `reservedQuantity`. A missing projection is represented as unknown, not zero or a larger catalog total. With no concrete branch selected, the catalog quantity is explicitly labeled and direct quantity changes are disabled.
- Retail pricing uses the current branch price resolver, including the concurrently introduced branch-commerce confirmation check. A missing price remains unavailable. Catalog discount treatment is shown only when the resolved price matches the catalog's discounted price.
- Cost visibility uses canonical active staff permission/scope with the existing active-admin exception. Both visible live-pet costs and the quantity pad's cost context use this gate.
- Simple quantity controls apply only to ordinary active quantity items. Lot-tracked items open lot management; individual units and live pets open the existing records/details flow.
- Live-pet labels show tracking and actual reservation counts. They do not infer health or quarantine from an available count.
- The existing quantity command envelope and callable remain unchanged. The cell stays pending through server readback at or beyond the returned projection revision. Success feedback follows that readback.
- Opening the quantity pad captures branch, quantity, and projection revision. A branch switch or changed balance/revision rejects the old absolute edit and asks the operator to review the current balance.
- Canonical staff authorization is checked again when the quantity command is submitted. Server authorization and audit remain authoritative.
- Existing detail/edit/delete, lot, quarantine, damage/mortality, protected availability, overflow, and POS navigation callbacks remain available through their existing owners.
- Each cell adds no Firebase listener, polling loop, independent image cache, or optimistic quantity arithmetic.

## Localization, layout, and accessibility

- Product name prefers Arabic in Arabic UI and English in English UI, then falls back to the available stored name.
- The screen owns RTL/LTR. Headings, metadata, portrait placement, panels, and wrapping controls follow logical leading/trailing.
- Prices, identifiers, and arithmetic controls retain their semantic direction. Arabic currency wording and translated captions remain localized.
- Metadata and controls wrap at narrow widths. Large accessibility text uses a vertical composition with unconstrained title height.
- Every interactive cell control has a minimum 44-point target. Detail opening is a real button with a label and hint; quantity actions have distinct VoiceOver names and stable identifiers.
- Availability is conveyed by text and a symbol, not color alone. Previous price and image count are named in the accessibility description.
- Press feedback respects Reduce Motion. Numeric transitions apply only to confirmed values on supported OS versions.
- The shared image loader uses a stable category placeholder for missing/loading/failed media, avoiding an indefinite failure spinner.

## Verification evidence

Run from `Pure Pets Admin`:

```sh
xcrun swiftc -frontend -parse PurePetsAdmin/AccessorySection/PPInventoryListView.swift PurePetsAdmin/BranchSection/PPBranchInventory.swift
plutil -lint PurePetsAdmin/ar.lproj/Localizable.strings PurePetsAdmin/en.lproj/Localizable.strings
python3 scripts/inventory_release_contract_static_test.py
git diff --check -- PurePetsAdmin/AccessorySection/PPInventoryListView.swift PurePetsAdmin/BranchSection/PPBranchInventory.swift PurePetsAdmin/ar.lproj/Localizable.strings PurePetsAdmin/en.lproj/Localizable.strings docs/stock/INVENTORY_CELL_REDESIGN_2026-09-21.md
```

The Command Center Admin source validator checks project membership, source policy, and native markers. A separate localization audit checks all keys referenced by the cell, unique new entries in both languages, and matching format placeholders. These are source checks, not Swift typechecking, a native build, rendered evidence, or production execution.

Task evidence is in `/tmp/pp-inventory-cells-20260921/`. The deterministic dispatch identified Admin but classified the broad redesign wording as a backend contract change. Its original result is retained. The implementation follows the user's explicit instruction to preserve workflows and contracts; no backend edit was inferred from that heuristic. Automated release/signed-evidence certification is not claimed.

## Remaining acceptance gate

The connected device was verified as an iPhone 13 Pro Max. Build permission was requested under the user-supplied AGENTS rule, “Never run a test build unless the user explicitly permits it.” No build was run in this task's static-validation phase.

Once authorized, use the approved physical-device workflow and default Xcode DerivedData. Verify:

1. Arabic RTL and English LTR: accessories, food, quantity-tracked live pets, individual live pets, and legacy records without an explicit tracking mode.
2. Compact width, long names/metadata/identifiers/prices, light/dark appearance, and the largest Dynamic Type size. Confirm controls wrap within family rows as well as standalone rows.
3. VoiceOver detail/action order, button labels, previous-price meaning, and minimum targets. Repeat with Reduce Motion enabled.
4. Confirmed, zero, low, read-only, inactive, missing, cached/unconfirmed, pending, denied, and readback-failure states.
5. Quantity pad open during a branch change or inventory revision change; repeated taps while pending; navigation away during readback; recovery by refresh after failure.
6. Existing lot/animal/quarantine/damage/delete/detail actions and navigation to POS. Any mutation exercise requires a controlled authorized test record.
7. Scroll/image performance and listener/request counts on the physical device. No profiling result has been inferred from source structure.

Review the combined working tree before any commit or release because concurrent changes extend beyond this task.
