# Face ID Architecture Diagram

## System Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    Pure Pets Admin App                      │
└─────────────────────────────────────────────────────────────┘
                            │
                ┌───────────┴───────────┐
                │                       │
         ┌──────▼──────┐         ┌──────▼──────┐
         │  SceneDelegate         │AdminLoginVC │
         │              │         │              │
         │ Foreground   │         │ Login Flow   │
         │ Lock         │         │ Auto-Auth    │
         └──────────────┘         └──────────────┘
                │                       │
                │       ┌───────────────┤
                │       │               │
         ┌──────▼───────▼──────────┐
         │    PPBiometric          │
         │    (Singleton Service)  │
         └──────────────┬──────────┘
                        │
        ┌───────────────┼───────────────┐
        │               │               │
   ┌────▼─────┐  ┌─────▼──────┐  ┌────▼──────┐
   │LocalAuth  │  │  Keychain  │  │ Credentials│
   │Framework  │  │  (Secure)  │  │  Storage   │
   │           │  │            │  │            │
   │Face ID/   │  │Email+Pass  │  │ Encrypted  │
   │Touch ID   │  │(Protected) │  │ at Rest    │
   └────┬──────┘  └─────┬──────┘  └────┬───────┘
        │                │              │
        └────────────────┼──────────────┘
                         │
                    Firebase Auth
                    (FIRAuth)
```

## Login Flow Sequence Diagram

```
User                AdminLoginVC         PPBiometric         Keychain       Firebase
│                        │                    │                 │              │
├─ Manual Login ────────>│                    │                 │              │
│                        │                    │                 │              │
│                        ├──────────────────────────────────────────────────>│
│                        │                                                    │
│                        │<─ Auth Success ─────────────────────────────────┤
│                        │                    │                 │              │
│                        ├─ enableBiometric ─>│                 │              │
│                        │    (email, pass)   │                 │              │
│                        │                    ├─ Prompt Face ID ┤              │
│                        │                    │                 │              │
│<─ Face ID Prompt ──────┤                    │                 │              │
│                        │                    │                 │              │
├─ Scan Face ──────────────────────────────>│                 │              │
│                        │                    │                 │              │
│                        │<─ Biometric OK ───┤                 │              │
│                        │                    │                 │              │
│                        │                    ├─ Store Creds ──>│              │
│                        │                    │  (Encrypted)    │              │
│                        │                    │<─ Success ──────┤              │
│                        │                    │                 │              │
│<─ Auto-Login ─────────┤                    │                 │              │
│   (Next Launch)        │                    │                 │              │
```

## App Foreground Lock Sequence

```
User          SceneDelegate       PPBiometric         Keychain
│                  │                   │                 │
├─ App goes ──────>│                   │                 │
│   background     │                   │                 │
│                  │                   │                 │
├─ App returns ────>│                   │                 │
│  to foreground    │                   │                 │
│                  │                   │                 │
│                  ├─ Show Lock ──────>│                 │
│                  │ Overlay           │                 │
│                  │                   │                 │
│<─ Lock Screen ───┤                   │                 │
│                  │                   │                 │
├─ Tap Unlock ─────>│                   │                 │
│                  ├─ Auth User ──────>│                 │
│                  │ Presence          ├─ Check Creds ──>│
│                  │                   │                 │
│<─ Face ID Prompt ┼───────────────────┤                 │
│                  │                   │                 │
├─ Scan Face ──────────────────────────>│                 │
│                  │                   │                 │
│                  │<─ Success ────────┤                 │
│                  │                   │                 │
│<─ Unlock & ──────┤                   │                 │
│   Show App       │                   │                 │
```

## Data Flow: Credential Storage

```
User Credentials
    │
    ├─ Email + Password
    │
    ▼
NSMutableDictionary
    │
    ├─ @{kPPBioEmailKey: email,
    │    kPPBioPasswordKey: password}
    │
    ▼
NSKeyedArchiver
    │
    ├─ Serialize to NSData
    │
    ▼
Keychain SecItemAdd
    │
    ├─ kSecClass: Generic Password
    ├─ kSecAttrService: com.purepets.admin.biometric
    ├─ kSecAttrAccount: admin_login_credentials
    ├─ kSecValueData: [Encrypted NSData]
    ├─ kSecAttrAccessControl: BiometryCurrentSet
    │
    ▼
iOS Keychain
    │
    └─ Encrypted at Rest
       Accessible only with Face ID/Touch ID
```

## Error Handling Flow

```
Biometric Authentication Attempt
          │
          ▼
    ┌─────────────────────┐
    │ LAContext Evaluate  │
    │ Policy              │
    └──────┬──────────────┘
           │
        ┌──┴──────────────────────┐
        │                         │
    Success              Error Occurred
        │                         │
        ▼                         ▼
   Get Credentials         Parse LAError
        │                         │
   ┌────┴────┐            ┌──────┴──────┐
   │ Valid? │            │  Error Type  │
   └────┬────┘            └──────┬──────┘
        │                         │
    ┌───┴────────┐        ┌───────┴────────────┐
    │            │        │                    │
  YES           NO   NotAvailable        UserCancel
    │            │        │                    │
    │            ▼        ▼                    ▼
    │      Disable     Show Error          Show Login
    │      Face ID     Message             Screen
    │            │        │                    │
    └─────┬──────┘        └────────┬───────────┘
          │                        │
          ▼                        ▼
    Require          User Chooses
    Manual Login       Action
```

## State Machine: Face ID Lifecycle

```
┌──────────────────────────────────────────────────────────┐
│                 FACE ID DISABLED                         │
│          (No Credentials Stored)                         │
└────────┬───────────────────────────────────┬─────────────┘
         │                                   │
         │ User logs in manually             │ (Auto)
         │                                   │
         ▼                                   │
┌──────────────────────────────────────────┐ │
│  AUTHENTICATING FIRST TIME               │ │
│  (Login successful,                      │ │
│   Face ID available)                     │ │
└────────┬───────────────────┬─────────────┘ │
         │                   │                │
    Enable               Cancel or             │
    Face ID             Device Error          │
         │                   │                │
         ▼                   └────────┬────────┘
┌──────────────────────────────────┐ │
│  FACE ID ENABLED                 │ │
│  (Credentials Secured            │ │
│   in Keychain)                   │ │
└────┬───────────────────────────┬─┘ │
     │                           │   │
     │ Next login                │   │
     │ (Auto-prompt for         │   │
     │  Face ID)                │   │
     │                           │   │
     ▼                           ▼   │
┌──────────────────┐    ┌──────────────────────┐
│ FACE ID ACTIVE   │    │ BIOMETRIC DISABLED   │
│ (Auto-Auth)      │    │ UNTIL MANUAL LOGIN   │
└──────────────────┘    │ (Invalid creds/      │
                        │  Failed auth)        │
                        └──────────┬───────────┘
                                   │
                    User logs in manually
                            │
                            ▼
                    ┌──────────────────┐
                    │ Face ID Re-enable │
                    │ Offered Again     │
                    └──────────────────┘
```

## Component Responsibilities

```
┌─────────────────────────────────────────────────────────┐
│                 PPBiometric Service                     │
├─────────────────────────────────────────────────────────┤
│ Responsibilities:                                       │
│ • Manage Face ID/Touch ID availability                 │
│ • Store credentials securely in Keychain               │
│ • Authenticate user with biometric                     │
│ • Retrieve credentials after auth                      │
│ • Clear stored credentials                             │
│ • Handle all biometric-specific errors                 │
│ • Provide user-friendly error messages                 │
└─────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────┐
│            AdminLoginViewController                     │
├─────────────────────────────────────────────────────────┤
│ Responsibilities:                                       │
│ • Present login UI                                     │
│ • Validate user input                                  │
│ • Call Firebase auth                                   │
│ • Enable Face ID after success                         │
│ • Auto-prompt for Face ID on launch                    │
│ • Manage login form state                              │
│ • Save email for convenience                           │
└─────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────┐
│              SceneDelegate                              │
├─────────────────────────────────────────────────────────┤
│ Responsibilities:                                       │
│ • Detect app background/foreground                     │
│ • Show foreground lock screen                          │
│ • Prompt for biometric to unlock                       │
│ • Manage lock overlay UI                               │
│ • Handle auth state transitions                        │
│ • Route to correct screen based on auth state          │
└─────────────────────────────────────────────────────────┘
```

## Security Model

```
┌────────────────────────────────────────────────────┐
│ iOS Keychain (Encrypted at Rest)                  │
├────────────────────────────────────────────────────┤
│                                                    │
│  ┌──────────────────────────────────────────┐    │
│  │ Email + Password                         │    │
│  │ (NSData - Encrypted)                     │    │
│  └──────────────────────────────────────────┘    │
│                                                    │
│  Access Control: kSecAccessControlBiometryCurrentSet
│  ├─ Requires device to be unlocked with           │
│  │  registered biometric (Face ID/Touch ID)       │
│  └─ If biometric enrollment changes,              │
│     credentials become inaccessible               │
│                                                    │
└────────────────────────────────────────────────────┘
        │
        ├─ Only accessible via
        │  LocalAuthentication Framework
        │
        ├─ Cannot be read directly
        │
        └─ Cannot be backed up to cloud
           (device-specific)
```

## Integration Points

```
Firebase Authentication
        │
        ├─ Sign in with email/password
        │
        └─ Returns FIRUser object
                │
                ▼
        AdminLoginViewController
                │
    ┌───────────┼────────────┐
    │           │            │
    ├─ Sign in success
    │           │
    ├──────────────────────────────────┐
    │                                  │
    │    ┌──────────────────────────┐  │
    │    │ Ensure user doc exists   │  │
    │    │ Check permissions        │  │
    │    └──────────────┬───────────┘  │
    │                  │               │
    │    ┌─────────────┴────────────┐  │
    │    │ Admin allowed?           │  │
    │    └─────────────┬────────────┘  │
    │                  │               │
    │     YES ─────────┼─────────────────┐
    │                  │                 │
    │     NO ──────────┼─────────────────┐
    │                  │                 │
    │    ┌─────────────▼─────────────┐   │
    │    │ Start user listener       │   │
    │    │ (Combined streams)        │   │
    │    └─────────────┬─────────────┘   │
    │                  │                 │
    │    ┌─────────────▼────────────────┐│
    │    │ [PPBiometric.shared         │││
    │    │  enableBiometricWithEmail:  │││
    │    │  password:]                 │││
    │    └────────────────────────────┘││
    │                                   │
    └───────────────────────────────────┘
                    │
                    ▼
            SceneDelegate
                    │
        ┌───────────┴────────────┐
        │                        │
        ├─ Update root view      ├─ Set lock requirements
        │                        │
        └────────┬───────────────┘
                 │
                 ▼
        AdminDashboardViewController
                 │
                 ├─ User can toggle Face ID
                 │  in settings
                 │
                 └─ Calls [PPBiometric.shared
                     disableBiometric]
```

This architecture ensures:
- **Security:** Credentials never leave Keychain
- **UX:** Seamless biometric experience
- **Reliability:** Proper fallbacks and error handling
- **Maintainability:** Clear separation of concerns
