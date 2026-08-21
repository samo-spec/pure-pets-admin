# Pure Pets Admin — SwiftyMax V6 UI Traversal

Branch: `redesign/admin-ui-v6-traversal`
Baseline: `main` @ `f916cff16c9b265be2d00b35fc64c9023deacc0b`

## Operating constraints

- Preserve Firebase, IAM, permissions, models, analytics, persistence, service contracts, and route identifiers.
- Reuse `PPDesignTokens`, `AdminSurface`, `AdminType`, `PPGlobalNavigation`, existing UIKit controllers, and the active Command Center V6 handoff.
- iOS 15 minimum.
- Native `xcodebuild`/device proof is currently blocked by the repository-recorded host safety gate. Source parsing/static validation can close source-level gates only; it cannot be reported as native build/render proof.

## Traversal order

### 0. Authenticated root / global shell
- [ ] `AdminAppRoot` restoring/error shell
- [ ] `AdminAppShell`
- [ ] five-tab bottom navigation
- [ ] permission-denied alert
- [ ] logout confirmation
- [ ] full-screen legacy route container/global route chrome

### 1. Command tab
- [ ] Command Center root (`CommandOrbitDirect.swift` active presentation)
- [ ] direct priority signal routes
- [ ] Command Center empty/loading/partial/error states

### 2. Work tab
- [ ] Work module index
- [ ] Payments
- [ ] Payment Settings
- [ ] Fulfillment
- [ ] POS Fast Sell
- [ ] POS History
- [ ] Accessories
- [ ] Food
- [ ] Live Pets
- [ ] descendants reachable from each screen

### 3. Operations tab
- [ ] Operations module index
- [ ] Delivery
- [ ] Provider Applications
- [ ] Provider Plans
- [ ] Provider Features
- [ ] Provider Accounting
- [ ] Branches
- [ ] Agents
- [ ] Home Control
- [ ] Services
- [ ] Veterinarians
- [ ] Moderation
- [ ] descendants reachable from each screen

### 4. People tab
- [ ] People module index
- [ ] Users
- [ ] Staff
- [ ] Chats
- [ ] descendants reachable from each screen

### 5. More tab
- [ ] More root/account summary
- [ ] My Account
- [ ] Notifications
- [ ] Notification Composer
- [ ] Notification Settings
- [ ] Accounting
- [ ] Audit
- [ ] Categories
- [ ] Banners
- [ ] Listings
- [ ] Settings
- [ ] language control
- [ ] logout control
- [ ] descendants reachable from each screen

### 6. Shared/global surfaces
- [ ] search
- [ ] filters
- [ ] sheets/action sheets
- [ ] alerts/confirmations
- [ ] empty/loading/error states
- [ ] forms
- [ ] status components
- [ ] common list rows/cards/buttons
- [ ] Dynamic Type / VoiceOver / contrast / Reduce Motion / RTL review

## Screen scorecard

Every reviewed screen records:
- hierarchy /20
- spacing /20
- typography /15
- component consistency /15
- interaction /15
- accessibility /10
- brand coherence /5

Native-only criteria remain `UNVERIFIED` until exact-byte device/build/render evidence exists.
