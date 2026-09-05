# Pure Pets Admin

> **Internal staff administration app for the Pure Pets platform.**

[![Platform](https://img.shields.io/badge/platform-iOS-005A9C)]()
[![Min Deployment Target](https://img.shields.io/badge/iOS-15.0+-blue)]()
[![Languages](https://img.shields.io/badge/languages-Objective--C_~95%25_%7C_Swift_~5%25-orange)]()
[![Firebase Project](https://img.shields.io/badge/Firebase-pure--pets--49199-yellow)]()
[![Scheme](https://img.shields.io/badge/scheme-PurePetsAdmin-critical)]()
[![License](https://img.shields.io/badge/license-Proprietary-red)]()

---

## Table of Contents

- [Overview](#overview)
- [Features](#features)
- [Architecture](#architecture)
- [Folder Structure](#folder-structure)
- [Technology Stack](#technology-stack)
- [Requirements](#requirements)
- [Installation](#installation)
- [Configuration](#configuration)
- [Build](#build)
- [Running](#running)
- [Project Structure](#project-structure)
- [Module Documentation](#module-documentation)
- [Data Flow](#data-flow)
- [Database](#database)
- [API](#api)
- [Authentication](#authentication)
- [Notifications](#notifications)
- [Background Tasks](#background-tasks)
- [Caching](#caching)
- [Offline Support](#offline-support)
- [Permissions](#permissions)
- [Error Handling](#error-handling)
- [Logging](#logging)
- [Security](#security)
- [Performance](#performance)
- [Accessibility](#accessibility)
- [UI/Design System](#uidesign-system)
- [Dependencies](#dependencies)
- [Testing](#testing)
- [Known Limitations](#known-limitations)
- [Future Improvements](#future-improvements)
- [Troubleshooting](#troubleshooting)
- [FAQ](#faq)
- [Changelog](#changelog)
- [License](#license)

---

## Overview

Pure Pets Admin is the internal iOS staff application for managing the Pure Pets ecosystem. It provides a secure administrative dashboard for processing orders, managing banners, services, veterinarians, notifications, delivery companies, accessories, branches, and agents. The app enforces a three-layer security model — App Check, Firebase Authentication (email/password + Google Sign-In), and a role-based permission system backed by the `staff_users` Firestore collection. The codebase is approximately 95% Objective-C with two Swift bridge files, uses UIKit code-only (no storyboards except a legacy splash entry point), and follows an MVC architecture with singleton service managers.

---

## Features

- **Staff Authentication & Biometric:** Email/password and Google Sign-In with Face ID / Touch ID credential storage via Keychain.
- **Role-Based Access Control:** 40+ permission keys across 20+ modules, enforced by `PPStaffAuth` and `RPManager`.
- **Payment Management:** Full order lifecycle (transitions, requests, audit trail, timeline, filtering, search).
- **Banner Management:** CRUD for main banners and child banners (`MainBannersViewsCol`).
- **Service Management:** Observe, add, update, moderate, and archive training/grooming service offers.
- **Veterinarian Management:** Manage personal and company vet profiles with subscription tiers (Free / Basic / Premium).
- **Notification Management:** Token management, audience-targeted push sends, and an in-app inbox.
- **Delivery Company Management:** Dashboard and Cloud Function bridge for delivery operations.
- **Accessory Management:** CRUD for the `petAccessories` inventory collection.
- **Audit Trail:** All sensitive writes are recorded in `AdminAuditLogs` with before/after snapshots via Cloud Functions.
- **Foreground Lock:** Infrastructure for Face ID re-authentication on app resume (currently disabled).

---

## Architecture

| Layer | Technology |
|-------|-----------|
| **UI** | UIKit (code-only), XLForm-driven CRUD screens |
| **Architecture Pattern** | MVC + Singleton Services |
| **App Delegate / Scene Delegate** | `SceneDelegate` owns root routing: `AppRootSplash` → `AppRootLogin` → `AppRootDashboard` |
| **Navigation** | Single `UINavigationController` stack; dashboard is XLForm-based where rows act as the navigation menu |
| **Deep Linking** | Push notification payloads with `route=payments_order` + `orderId` |
| **State Management** | Singleton managers (`AppMgr`, `FUM`, `RPM`, `UsrMgr`) |
| **Networking** | Firebase SDK, `FIRFunctions` HTTPSCallable for sensitive writes |
| **Persistence** | Not detected in current source |

### Root Routing Flow

```
SceneDelegate
  └─ AppRootSplash (animated splash)
      └─ AppRootLogin (auth gate)
          └─ AppRootDashboard (XLForm menu)
              └─ UINavigationController stack
```

### Key Singletons

| Macro | Class | Responsibility |
|-------|-------|---------------|
| `AppMgr` | `AppManager` | Firebase boot, App Check chain, admin verification, MainKinds fetch, dashboard counts |
| `FUM` | `FUManager` | Auth lifecycle, user document CRUD, user listing |
| `RPM` | `RPManager` | Permission listener, role change monitoring, ID token claims |
| `UsrMgr` | `UserManager` | User lifecycle — fetch, cache, listen, admin toggle |

---

## Folder Structure

```
Pure Pets Admin/
├── Pure Pets Admin/
│   ├── AppDelegate/
│   ├── SceneDelegate/
│   ├── UsersSection/
│   │   ├── UserController/
│   │   │   ├── Login/                    # Login screens, permission editors, staff management
│   │   │   └── StaffManagement/
│   │   ├── References/
│   │   │   ├── UserManager/
│   │   │   └── UserModel/
│   │   └── SecFil/                       # Security layer files
│   │       ├── FUManager/
│   │       ├── RPManager/
│   │       ├── PPStaffAuth/
│   │       ├── PPBiometric/
│   │       └── AdminService/
│   ├── Payments/
│   │   ├── PPPaymentManagementService/   # Order transitions, requests, audit
│   │   ├── PPPaymentManagementModels/    # Filter, settings, timeline, audit, models
│   │   ├── PPPaymentManagementViewController/  # Search, filter, paginated list
│   │   └── PPPaymentDetailsViewController/      # Overview, actions, items, timeline, audit
│   ├── Banners/
│   │   ├── PPBannersManager/
│   │   ├── MainBannerModel/
│   │   ├── PPBannerViewModel/
│   │   ├── PPBannersListVC/
│   │   ├── PPAddBannerViewController/
│   │   ├── PPBannerCell/
│   │   ├── PPBannersCollection/
│   │   └── PPBannerView/
│   ├── ServicesSection/
│   │   ├── PPServiceManager/
│   │   ├── PPServiceModel/
│   │   ├── PPServicesListViewController/
│   │   ├── PPServiceDetailViewController/
│   │   └── PPAddEditServiceViewController/
│   ├── VeterinarianSection/
│   │   ├── PPVetManager/
│   │   ├── PPVetModel/
│   │   ├── PPVetsListViewController/
│   │   ├── PPVetDetailViewController/
│   │   ├── PPAddEditVetViewController/
│   │   └── PPVetSubscriptionViewController/
│   ├── NotificationsSection/
│   │   ├── PPNotificationsManager/
│   │   ├── NotificationManager/
│   │   ├── NotificationModel/
│   │   ├── NotificationsListViewController/
│   │   ├── AdminNotificationComposerView (SwiftUI)/
│   │   ├── AdminNotificationSettingsView (SwiftUI)/
│   │   └── PPProInAppNotificationPresenter/
│   ├── DeliveryCompanySection/
│   │   ├── DeliveryCompanyManager/
│   │   ├── DeliveryCompanyConstants/
│   │   ├── DeliveryCompanyModels/
│   │   └── DeliveryCompanyDashboardViewController/
│   ├── AccessorySection/
│   │   ├── AccessoryManager/
│   │   ├── AccessoriesListViewController/
│   │   ├── AddAccessoryViewController/
│   │   └── PetAccessory/
│   ├── BranchSection/
│   │   └── PPBranchModel/
│   ├── AgentSection/
│   │   └── PPAgentModel/
│   ├── Supporting Files/
│   │   ├── PrefixHeader.pch
│   │   └── Info.plist
│   └── Assets/
│       ├── ColorsAssets.xcassets/
│       └── AppIcon.appiconset/
├── Pure Pets Admin.xcodeproj/
├── PurePetsAdmin.xcworkspace/
├── Podfile
├── PurePetsAdminTests/
└── PurePetsAdminUITests/
```

---

## Technology Stack

### Languages
- **Objective-C:** ~95% of the codebase
- **Swift:** ~5% (2 files: `PPProLoginHostingController.swift`, `PPEditorBridge.swift`)

### Frameworks & SDKs
- **UIKit** — Code-only UI (no storyboards except legacy `Main.storyboard` splash entry)
- **XLForm** — Form-based CRUD screens
- **YYKit** — Utility components (unmaintained, warning suppression applied)
- **SDWebImage** — Asynchronous image loading
- **lottie-ios ~> 2.5.3** — Vector animations
- **IQKeyboardManager** — Keyboard avoidance
- **SSZipArchive** — Archive utilities
- **PopupDialog ~> 1.1** — Modal dialogs
- **JGProgressHUD** — Loading indicators
- **JDStatusBarNotification** — Status bar notifications
- **TOCropViewController** — Image cropping
- **ShowTime (DEBUG only)** — Touch visualization for demos

### Backend
- **Firebase Core / Auth / Firestore / Storage / Messaging / Functions / AppCheck / Installations**
- **GoogleSignIn 8.0.0**
- **Cloud Functions** — HTTPSCallable wrappers for all sensitive writes (audit logging)

---

## Requirements

- **Xcode:** 16+
- **Minimum iOS Target:** 15.0
- **CocoaPods:** 1.15+ (recommended)
- **Ruby:** Bundled with macOS (for CocoaPods)
- **Node.js:** 22+ (for Firebase emulators and Cloud Functions validation)
- **Firebase Project:** `pure-pets-49199` (access required)
- **Apple Developer Account:** For push notification entitlements and App Attest

---

## Installation

### 1. Clone the Repository

```bash
git clone <repository-url>
cd "Pure Pets Admin"
```

### 2. Install CocoaPods Dependencies

```bash
pod install
```

> Always open `PurePetsAdmin.xcworkspace` — never the `.xcodeproj`.

### 3. Install Firebase CLI (for emulators / rules deployment)

```bash
npm install -g firebase-tools
firebase login
```

### 4. Open the Workspace

```bash
open PurePetsAdmin.xcworkspace
```

---

## Configuration

### Firebase

1. Download the latest `GoogleService-Info.plist` from the Firebase Console (`pure-pets-49199`).
2. Place it in `Pure Pets Admin/Supporting Files/`.
3. Verify the `APP_CLIP_GOOGLE_PLIST` build setting is updated if needed.

### Info.plist Keys

| Key | Value | Purpose |
|-----|-------|---------|
| `NSFaceIDUsageDescription` | Required string | Face ID permission prompt |
| `aps-environment` | `development` | Push notification environment |
| `CFBundleURLTypes` | Google Sign-In reverse client ID | Google Sign-In URL scheme |
| `UILaunchStoryboardName` | `Main` | Legacy splash entry point |

### Build Settings

| Setting | Value | Reason |
|---------|-------|--------|
| `SWIFT_INSTALL_OBJC_HEADER` | `NO` | Required by `FirebaseFirestore` for Xcode 16+ |
| `EXCLUDED_ARCHS[sdk=iphonesimulator*]` | `arm64` | Prevents simulator build failures |
| `CODE_SIGNING_ALLOWED` | `NO` (for CI) | Disable signing in CI environments |

---

## Build

### Device Build

```bash
xcodebuild -workspace 'PurePetsAdmin.xcworkspace' \
  -scheme 'PurePetsAdmin' \
  -configuration Debug \
  -destination 'generic/platform=iOS' \
  CODE_SIGNING_ALLOWED=NO build
```

### Simulator Build

```bash
xcodebuild -workspace 'PurePetsAdmin.xcworkspace' \
  -scheme 'PurePetsAdmin' \
  -configuration Debug \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.2' \
  CODE_SIGNING_ALLOWED=NO build
```

### Clean Build

```bash
xcodebuild clean -workspace 'PurePetsAdmin.xcworkspace' -scheme 'PurePetsAdmin'
```

---

## Running

### With Xcode

Select the `PurePetsAdmin` scheme, choose a target device or simulator, and press **⌘R**.

### Headless Build (CI)

```bash
xcodebuild -workspace 'PurePetsAdmin.xcworkspace' \
  -scheme 'PurePetsAdmin' \
  -configuration Debug \
  -destination 'generic/platform=iOS' \
  CODE_SIGNING_ALLOWED=NO build
```

> **Note:** Push notifications and Google Sign-In require a real device and valid code signing. Simulator builds will skip those features.

---

## Project Structure

### Entry Points

| File | Responsibility |
|------|---------------|
| `AppDelegate.swift` | UIApplication lifecycle, remote notification registration |
| `SceneDelegate.swift` | Window management, root routing |
| `PrefixHeader.pch` | Global imports (`AppMgr`, `GM`, `FUM`, `RPM`, `UsrMgr` macros) |
| `PPDesignTokens.h` | Design token macros (`PPSpaceBase`, `PPCornerCard`, `AppPrimaryClr`, etc.) |

### Swift → ObjC Bridge

Two Swift files are exposed via `Pure Pets Admin-Bridging-Header.h`:

- `PPProLoginHostingController.swift` — SwiftUI hosting controller for the Pro login flow
- `PPEditorBridge.swift` — Bridge for editor functionality

---

## Module Documentation

### UsersSection (`UsersSection/`)

Core user management and authentication module.

- **UserManager** (`UsrMgr`): User lifecycle — fetch, cache, listen, admin toggle.
- **FUManager** (`FUM`): Auth lifecycle, user document CRUD, user listing.
- **RPManager** (`RPM`): Permission listener, role change monitoring, ID token claims.
- **PPStaffAuth**: Staff authorization — reads `staff_users` collection, enforces 40+ permission keys.
- **PPBiometric**: Face ID / Touch ID integration with Keychain credential storage.
- **AdminService**: Cloud Function bridge for administrative operations.

### Payments (`Payments/`)

Complete order payment management workflow.

- **PPPaymentManagementService**: Order transitions, requests, audit logging.
- **PPPaymentManagementModels**: Filter, settings, timeline, audit, support request, and order record models.
- **PPPaymentManagementViewController**: Search, filter, paginated order list.
- **PPPaymentDetailsViewController**: Order overview, admin actions, items, requests, timeline, audit trail.
- **Settings Screens**: Payment-related configuration.

### Banners (`Banners/`)

CRUD management for `MainBannersViewsCol` and its child banner subcollection.

- **PPBannersManager**: Full CRUD operations.
- **MainBannerModel**: Banner data model.
- **PPBannerViewModel**: View model for banner display.
- **PPBannersListVC**: List view for all banners.
- **PPAddBannerViewController**: Banner creation/editing form.
- **PPBannerCell / PPBannersCollection / PPBannerView**: UI components.

### ServicesSection (`ServicesSection/`)

Management of training and grooming service offers.

- **PPServiceManager**: Observe, add, update, moderate, archive services.
- **PPServiceModel**: Training/Grooming services with verification status and subscription.
- **PPServicesListViewController**: Paginated service list.
- **PPServiceDetailViewController**: Service detail with moderation controls.
- **PPAddEditServiceViewController**: Service creation/editing form.

### VeterinarianSection (`VeterinarianSection/`)

Management of veterinarian profiles.

- **PPVetManager**: CRUD and subscription management.
- **PPVetModel**: Personal/Company vets with Free/Basic/Premium subscription tiers.
- **PPVetsListViewController**: Paginated vet list.
- **PPVetDetailViewController**: Vet detail view.
- **PPAddEditVetViewController**: Vet creation/editing form.
- **PPVetSubscriptionViewController**: Subscription plan management UI.

### NotificationsSection (`NotificationsSection/`)

Push notification management and in-app inbox.

- **PPNotificationsManager**: Token management, audience-targeted push sends.
- **NotificationManager**: Inbox CRUD operations.
- **NotificationModel**: Notification data model.
- **NotificationsListViewController**: Inbox list view.
- **AdminNotificationComposerView**: Flagship SwiftUI sovereign push notification composer.
- **AdminNotificationSettingsView**: Sovereign APNs gateway & channel notification settings cockpit.
- **PPProInAppNotificationPresenter**: In-app notification presentation.

### DeliveryCompanySection (`DeliveryCompanySection/`)

Delivery company management dashboard.

- **DeliveryCompanyManager**: Cloud Function bridge for delivery operations.
- **DeliveryCompanyConstants**: Status enums, role definitions, dashboard tab configuration.
- **DeliveryCompanyModels**: Delivery company data models.
- **DeliveryCompanyDashboardViewController**: Dashboard with tab-based navigation.

### AccessorySection (`AccessorySection/`)

Pet accessory inventory management.

- **AccessoryManager**: CRUD for `petAccessories` collection.
- **AccessoriesListViewController**: Inventory list view.
- **AddAccessoryViewController**: Accessory creation/editing form.
- **PetAccessory**: Accessory data model.

### BranchSection (`BranchSection/`)

- **PPBranchModel**: Branch data model only. Not detected in current source: dedicated branch list/detail screens.

### AgentSection (`AgentSection/`)

- **PPAgentModel**: Agent data model only. Not detected in current source: dedicated agent list/detail screens.

---

## Data Flow

```
User Action
  │
  ▼
ViewController → Manager (Singleton)
  │
  ├─ Read Path:      Firestore direct read (FIRFirestore)
  └─ Write Path:     FIRFunctions HTTPSCallable → Cloud Function → Firestore + AuditLog
       │
       ▼
  AdminAuditLogs (before/after snapshot)
```

### Read Flow

1. ViewController requests data from a Manager singleton.
2. Manager performs a `Firestore` query via `FIRFirestore`.
3. Data is returned as model objects.
4. ViewController updates UI on the main thread.

### Write Flow

1. ViewController calls Manager write method.
2. Manager invokes a `FIRFunctions` HTTPSCallable function.
3. Cloud Function validates auth → checks permission → performs write → creates audit log entry.
4. Result is returned to the Manager → ViewController.

---

## Database

### Firestore Collections

| Collection | Purpose |
|------------|---------|
| `UsersCol` | User accounts and profiles |
| `PermisstionsCol` | Permission definitions (typo is intentional and permanent) |
| `staff_users` | Staff authorization documents |
| `MainKindsCollection` | Pet main kinds / categories |
| `pet_ads` | Pet advertisement listings |
| `petAccessories` | Pet accessory inventory (single stock collection) |
| `branches` | Branch locations |
| `agents` | Platform agents |
| `Orders` | Customer orders |
| `Orders/{id}/events` | Order event timeline |
| `Orders/{id}/requests` | Order support requests |
| `AdminAuditLogs` | Administrative audit trail |
| `MainBannersViewsCol` | Main banner configurations |
| `MainBannersViewsCol/{id}/ChildBanners` | Child banner entries |
| `serviceOffers` | Training/grooming service offers |
| `veterinarians` | Veterinarian profiles |
| `admin/notifications/items` | Admin notification records |
| `users/{uid}/inbox` | Per-user notification inbox |

---

## API

### Cloud Functions (HTTPSCallable)

All sensitive writes go through Firebase Cloud Functions. The function names follow the pattern defined in `Pure Pets Infra/functions/`. Typical function chain:

```
validateAuth() → requirePermission("permission.key") → validate input → business logic → writeAuditLog({...})
```

### Firebase SDK Usage

| SDK | Usage |
|-----|-------|
| `FirebaseCore` | App initialization |
| `FirebaseAuth` | Email/password + Google Sign-In |
| `FirebaseFirestore` | All reads and simple writes |
| `FirebaseStorage` | Image/media upload |
| `FirebaseMessaging` | Push notification token management |
| `FirebaseFunctions` | HTTPSCallable wrappers for sensitive writes |
| `FirebaseAppCheck` | Device attestation (Debug → AppAttest → DeviceCheck) |
| `FirebaseInstallations` | FIS token management |
| `GoogleSignIn` | Google Sign-In flow |

---

## Authentication

### Methods

| Method | Status |
|--------|--------|
| Email / Password | ✅ Active |
| Google Sign-In | ✅ Active |
| Biometric (Face ID / Touch ID) | ✅ Active (Keychain credential storage) |

### Authentication Flow

1. User launches app → `AppRootSplash` → `AppRootLogin`.
2. User signs in via email/password or Google Sign-In.
3. `FUManager` (`FUM`) completes the Firebase Auth lifecycle.
4. `PPStaffAuth.fetchStaffDoc` verifies `accountType == "staff"` and `canAccessStaffWorkspace`.
5. `RPManager` (`RPM`) listens for permission changes and monitors ID token claims for role changes.
6. On success → route to `AppRootDashboard`.
7. On failure → stay on login screen with error messaging.

### Biometric Flow

- `PPBiometric` uses `LAContext` for Face ID / Touch ID evaluation.
- Credentials stored in Keychain (`kSecClass Generic Password`, service: `com.purepets.admin.biometric`).
- Foreground re-authentication infrastructure exists but is currently disabled.

---

## Notifications

### Push Notification Flow

1. App registers for remote notifications via `UIApplication.registerForRemoteNotifications()`.
2. Token is sent to `FirebaseMessaging`.
3. `PPNotificationsManager` handles token storage and audience-targeted sends.
4. Incoming notifications are displayed via `UNUserNotificationCenter`.
5. Deep linking: payload with `route=payments_order` + `orderId` navigates to `PPPaymentDetailsViewController`.

### Notification Modules

| Component | Purpose |
|-----------|---------|
| `PPNotificationsManager` | Token management, audience-targeted push composition and sending |
| `NotificationManager` | In-app inbox CRUD (mark read, delete, archive) |
| `NotificationModel` | Notification data model |
| `NotificationsListViewController` | Inbox UI |
| `AdminNotificationComposerView` | Flagship SwiftUI push notification composer |
| `AdminNotificationSettingsView` | Sovereign SwiftUI APNs gateway & channel settings cockpit |
| `PPProInAppNotificationPresenter` | In-app banner presentation |

---

## Background Tasks

Not detected in current source. The app does not implement `BGTaskScheduler` or background URL sessions. All network operations are foreground-only via Firebase SDKs.

---

## Caching

### SDWebImage

- Asynchronous image download and caching via `SDWebImage` (default `SDImageCache`).

### Firebase Firestore

- Firestore SDK provides built-in metadata caching, but **offline persistence is not explicitly configured** in the current source.

### UserManager Cache

- `UsrMgr` maintains an in-memory user cache for the current session.

---

## Offline Support

**Not configured.** Firestore offline persistence (`FirestoreSettings.cacheSettings`) is not explicitly enabled. The app requires network connectivity for all operations.

---

## Permissions

### Runtime Permissions

| Permission | Purpose | Status |
|------------|---------|--------|
| `NSFaceIDUsageDescription` | Face ID for biometric authentication | ✅ Configured |
| Push Notifications | Remote notification delivery | ✅ Configured |

### Hardware Access

- **Camera:** Not detected in current source.
- **Photo Library:** Not detected in current source.
- **Location:** Not detected in current source.

---

## Error Handling

- **Cloud Functions:** Errors returned as `NSError` objects from `FIRFunctions` HTTPSCallable calls, propagated to ViewControllers.
- **Network:** Firebase SDK handles retry internally for reads; write failures presented via `JGProgressHUD` or `JDStatusBarNotification`.
- **Auth:** `FUManager` handles Firebase Auth errors and surfaces user-friendly messages on the login screen.
- **Biometric:** `PPBiometric` evaluates `LAError` codes and maps to user-facing alerts.

---

## Logging

Not detected in current source. No structured logging framework (e.g., `CocoaLumberjack`, `os_log`) is configured. Administrative actions are logged to `AdminAuditLogs` in Firestore through Cloud Functions, but client-side debug logging is not formally implemented.

---

## Security

### Three-Layer Model

| Layer | Mechanism |
|-------|-----------|
| **1. App Check** | Resilient attestation chain: Debug → App Attest → DeviceCheck |
| **2. Biometric** | Face ID / Touch ID via `LAContext` + Keychain credential storage |
| **3. Authentication** | Firebase Auth (email/password + Google Sign-In) |

### Admin Gating

`PPStaffAuth.fetchStaffDoc` enforces:
- `accountType == "staff"`
- `canAccessStaffWorkspace == true`

### RBAC

- **UserRole enum** — 9 roles (0: Unknown → 8: SuperAdmin).
- **40+ permission keys** — String-based, checked via `RPManager`.
- **20+ modules** — Gated by permission keys.
- All permission checks performed client-side AND server-side (Cloud Functions).

### Audit Trail

Every sensitive write through Cloud Functions creates an entry in `AdminAuditLogs` with:
- User ID and role
- Timestamp
- Before/after snapshots
- Action type

### Foreground Lock

Infrastructure for Face ID re-authentication on app resume exists but is currently disabled.

### Additional Protections

- Firestore transactions for sensitive mutations.
- `GoogleService-Info.plist` must be kept out of version control (not committed).
- App Check enforced on all platforms.
- All Cloud Functions validate auth and permissions before executing.

---

## Performance

### Build Performance

- Precompiled Pods via CocoaPods.
- Remove `ShowTime` from release builds (DEBUG-only pod).
- `SWIFT_INSTALL_OBJC_HEADER = NO` prevents unnecessary Swift header generation.

### Runtime

- XLForm-based dashboard loads all menu rows at once — minimal overhead.
- `SDWebImage` handles image caching automatically.
- No observed memory leaks from singleton managers.
- No background fetch or task overhead (foreground-only app).

### Known Performance Considerations

- YYKit is unmaintained — may introduce App Store validation warnings.
- Firestore queries without pagination on large collections could cause UI stutter.

---

## Accessibility

Not detected in current source. The app does not explicitly implement:
- `UIAccessibility` labels or traits on custom views.
- Dynamic Type support.
- VoiceOver rotor or custom actions.
- Reduced motion handling.

---

## UI/Design System

### Design Tokens

- Defined in `PPDesignTokens.h`.
- Macros include `PPSpaceBase`, `PPCornerCard`, `AppPrimaryClr`, etc.
- No magic numbers — all spacing, colors, and corner radii use token macros.

### Global Utilities

| Macro | Class | Purpose |
|-------|-------|---------|
| `GM` | `GM` (global stateless) | Fonts, colors, image loading, shadows |
| `AppMgr` | `AppManager` | Firebase state, session, counts |
| `kLang(@"key")` | `PPAppLanguage` | Localized string lookup (Arabic primary, English secondary) |

### RTL Support

- Arabic is the primary language with full RTL layout.
- Leading/trailing Auto Layout anchors used instead of left/right.
- `kLang(@"key")` macro handles string localization.

### Third-Party UI Components

- **XLForm** — Form-based CRUD screens (dashboard menu, settings, editors).
- **PopupDialog** — Modal alert dialogs.
- **JGProgressHUD** — Loading indicators.
- **JDStatusBarNotification** — Status bar notifications.
- **lottie-ios 2.5.3** — Vector animations.
- **TOCropViewController** — Image cropping.

---

## Dependencies

### CocoaPods (`Podfile`)

```ruby
# Core
pod 'YYKit'
pod 'SDWebImage'
pod 'lottie-ios', '~> 2.5.3'
pod 'XLForm'
pod 'IQKeyboardManager'
pod 'SSZipArchive'

# UI
pod 'PopupDialog', '~> 1.1'
pod 'JGProgressHUD'
pod 'JDStatusBarNotification'
pod 'TOCropViewController'

# Debug
pod 'ShowTime', :configurations => ['Debug']

# Firebase
pod 'Firebase/Core'
pod 'Firebase/Auth'
pod 'Firebase/Firestore'
pod 'Firebase/Storage'
pod 'Firebase/Messaging'
pod 'Firebase/Functions'
pod 'Firebase/AppCheck'
pod 'Firebase/Installations'
pod 'GoogleSignIn', '~> 8.0.0'
```

---

## Testing

### Unit Tests (`PurePetsAdminTests`)

- **Payment Workflow State Validation** — XCTest cases for order state transitions.
- Coverage does not include `UserManager`, `PPBiometric`, or individual Manager classes.

### UI Tests (`PurePetsAdminUITests`)

- Basic launch tests (XCUITest).
- No integration or snapshot tests.

### Run Tests

```bash
xcodebuild test \
  -workspace 'PurePetsAdmin.xcworkspace' \
  -scheme 'PurePetsAdmin' \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.2'
```

---

## Known Limitations

1. **YYKit unmaintained** — Last updated 2018. Warning suppression applied. May cause App Store validation warnings.
2. **FirebaseFirestore + Xcode 16** — Requires `SWIFT_INSTALL_OBJC_HEADER = NO` to avoid compilation errors.
3. **Simulator arm64 exclusion** — `arm64` excluded on simulator; QIB-like framework constraints (not applicable here, but pattern inherited).
4. **No dependency injection** — All services are singletons (global mutable state). Testability is limited.
5. **Significant commented-out dead code** — Several files contain large commented code blocks from previous iterations.
6. **No offline persistence** — Firestore `cacheSettings` not configured. App fails without network.
7. **No tab bar or coordinators** — Single navigation stack. No modular coordinator pattern.
8. **No structured logging** — No `os_log` or `CocoaLumberjack` integration. Debugging relies on `NSLog`.
9. **No accessibility** — `UIAccessibility` traits and Dynamic Type not implemented.
10. **Limited test coverage** — Only payment state validation is covered. All managers lack unit tests.
11. **Foreground biometric lock disabled** — Infrastructure exists but is not active.
12. **No background tasks** — `BGTaskScheduler` not implemented.

---

## Future Improvements

- [ ] Replace `YYKit` with modern replacements (e.g., `SwiftGen`, differences).
- [ ] Enable Firestore offline persistence.
- [ ] Add coordinator pattern for navigation.
- [ ] Implement `os_log` structured logging.
- [ ] Add `UIAccessibility` support and Dynamic Type.
- [ ] Enable foreground biometric lock.
- [ ] Increase unit test coverage for all Manager classes.
- [ ] Add `BGTaskScheduler` for background data refresh.
- [ ] Remove commented-out dead code.
- [ ] Migrate from XLForm to a modern form library.
- [ ] Update lottie-ios from 2.5.3 to latest.
- [ ] Add CI/CD pipeline with automated test execution.
- [ ] Implement snapshot/UI integration tests.

---

## Troubleshooting

| Problem | Cause | Solution |
|---------|-------|----------|
| Build fails on simulator | `arm64` excluded for simulator | Ensure `EXCLUDED_ARCHS` is set in build settings |
| Firebase compile error | `SWIFT_INSTALL_OBJC_HEADER` conflict | Set to `NO` in build settings |
| CocoaPods `pod install` fails | Ruby version or outdated CocoaPods | Run `sudo gem install cocoapods` |
| Google Sign-In not working | Missing URL scheme in Info.plist | Add `CFBundleURLTypes` with reversed client ID from `GoogleService-Info.plist` |
| Push notifications not delivered | Missing `aps-environment` entitlement or code signing | Verify provisioning profile includes push capability |
| Face ID not prompting | `NSFaceIDUsageDescription` missing | Add the key to `Info.plist` |
| App crashes on launch | Missing `GoogleService-Info.plist` | Download from Firebase Console and add to project |
| Dashboard rows not loading | App Check attestation failure | Check Firebase Console App Check settings for the project |

---

## FAQ

**Q: Why is `PermisstionsCol` misspelled?**  
A: The typo is intentional and permanent. Do not rename this collection — it is referenced across all platform code, Firestore rules, and Cloud Functions.

**Q: Why no storyboards?**  
A: The app uses code-only UIKit. The only exception is the legacy `Main.storyboard` splash entry point. Do not add new storyboards.

**Q: Can I add a new Swift file?**  
A: Yes, but it must be declared in `Pure Pets Admin-Bridging-Header.h` to be callable from Objective-C. Use `@objc` attributes as needed.

**Q: How do I add a new Firebase collection?**  
A: Add the collection reference in `AppManager` or the relevant Manager class. Update Firestore rules in `Pure Pets Infra/`. Add Cloud Function permissions if writes are sensitive.

**Q: Why is there no `writeBatch` usage?**  
A: By convention, all Firestore mutations go through individual `updateDoc` calls or Cloud Functions. This is a platform-wide rule.

**Q: How do I add a new permission key?**  
A: Add the key string to the `staff_users` document for the target staff member. Update `RPManager` to check the new key. Add server-side validation in the relevant Cloud Function.

---

## Changelog

### 1.0.0 — Initial Release
- Staff authentication with email/password and Google Sign-In.
- Biometric Face ID / Touch ID login.
- Role-based access control with 40+ permission keys.
- Payment management with full order lifecycle, audit trail, and search/filter.
- Banner CRUD management.
- Service offer management (training/grooming).
- Veterinarian profile management with subscription tiers.
- Push notification management and inbox.
- Delivery company dashboard.
- Pet accessory inventory CRUD.
- Three-layer security (App Check, Biometric, Auth).
- Cloud Functions integration for sensitive writes with audit logging.

---

## License

**Proprietary.** All rights reserved. Pure Pets Admin is an internal tool for authorized staff of the Pure Pets platform. Unauthorized distribution or modification is prohibited.
