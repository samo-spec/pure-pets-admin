# Face ID Quick Reference

## Enable Face ID After Login Success

```objc
// In AdminLoginViewController.m - pp_finishLoginAndStartUserStreamWithEmail:password:showToast:fromBiometric:persistCredentials:
[PPBiometric.shared enableBiometricWithEmail:email password:password];
```

## Auto-Authenticate on App Launch

The AdminLoginViewController already implements this in `viewDidAppear:`:
- Checks if credentials are stored
- Checks if Face ID is not disabled
- Auto-prompts for Face ID
- Falls back to login screen if needed

## Manual Face ID Prompt

```objc
[PPBiometric.shared authenticateFrom:viewController
                               reason:@"Authenticate to login"
                           completion:^(NSString *email, NSString *password, NSError *error) {
    if (!error) {
        // Use email and password to sign in
    }
}];
```

## App Foreground Lock

In SceneDelegate.m:
- When app returns from background, `pp_armForegroundLockIfNeeded` activates the lock
- Lock overlay appears with "Unlock with Face ID" button
- Tapping button calls `pp_promptForegroundUnlockIfNeededForced:`
- Uses `authenticateUserPresenceWithReason:completion:` for unlock

## Disable Face ID

```objc
[PPBiometric.shared disableBiometric];
```

## Check if Available

```objc
if ([PPBiometric.shared isBiometricAvailable]) {
    LABiometryType type = [PPBiometric.shared biometryType];
    // type: LABiometryTypeFaceID, LABiometryTypeTouchID, LABiometryTypeNone
}
```

## Stored Credentials Check

```objc
if ([PPBiometric.shared hasStoredCredentials]) {
    // Face ID is enabled and credentials are available
}
```

## Error Handling

All completion blocks provide an NSError. Common errors:

- `LAErrorAuthenticationFailed` - User failed biometric
- `LAErrorUserCancel` - User cancelled prompt
- `LAErrorBiometryNotAvailable` - Device doesn't support
- `LAErrorBiometryNotEnrolled` - User hasn't set up biometric
- `LAErrorBiometryLockout` - Too many failed attempts

## Configuration

**Info.plist** - Already configured:
```xml
<key>NSFaceIDUsageDescription</key>
<string>Use Face ID to securely sign in to your admin account.</string>
```

## Keychain Details

- **Service:** `com.purepets.admin.biometric`
- **Account:** `admin_login_credentials`
- **Access Control:** Biometric (current set only)
- **Data Stored:** Email and password (encrypted)

## Testing Checklist

- [ ] Initial login works
- [ ] Face ID prompt appears after enabling
- [ ] App auto-authenticates on launch with Face ID
- [ ] App lock appears on foreground
- [ ] Face ID unlocks foreground lock
- [ ] Disabling Face ID removes credentials
- [ ] Failed biometric shows error message
- [ ] Cancelled biometric falls back to login
- [ ] Changing password disables Face ID
- [ ] Simulator: Hardware > Biometric Sensor > Face ID works

## Debugging

Enable Face ID logging by searching for `[Biometric]` in console:

```
[Biometric] Credentials stored successfully
[Biometric] Failed authentication: User cancelled
[Biometric] No stored credentials found
[Biometric] Biometric not available on device
```

## Security Notes

1. Credentials are only accessible with enrolled biometric
2. Enrolling new biometric makes old credentials inaccessible
3. Failed authentication with wrong password auto-disables Face ID
4. Credentials cleared on app update/reinstall
5. All data is encrypted at rest in Keychain
