//
//  FILE_HELPER_USAGE.md
//  PurePetsAdmin
//
//  Documentation for safe file I/O operations
//

# PPFileHelper - Safe File I/O Utilities

## Overview

`PPFileHelper` provides safe, permission-aware file reading utilities that gracefully handle common file access errors, particularly permission denied errors from system-protected files.

## Problem Solved

When attempting to read system-protected files (like `/private/var/Managed Preferences/mobile/com.apple.CoreMotion.plist`), iOS/macOS refuses access with a permission error. Instead of crashing or logging noisy errors, `PPFileHelper` returns `nil` silently for permission errors and only logs other error types.

## Usage

Since `PPFileHelper` is included in the prefix header, you can use it anywhere in the app without additional imports.

### 1. Safe Data Reading

```objective-c
// Read file as NSData
NSData *data = [PPFileHelper safeDataFromFile:@"/path/to/file.bin"];
if (data) {
    // Successfully read file
} else {
    // File doesn't exist, not readable, or permission denied
}
```

### 2. Safe String Reading

```objective-c
// Read text file as NSString
NSString *content = [PPFileHelper safeStringFromFile:@"/path/to/file.txt"];
if (content) {
    // Successfully read file as UTF-8 (falls back to ISO-Latin1 if needed)
}
```

### 3. Safe Plist Reading

```objective-c
// Read and parse .plist file
id plist = [PPFileHelper safePlistFromFile:@"/path/to/file.plist"];
if ([plist isKindOfClass:[NSDictionary class]]) {
    NSDictionary *dict = (NSDictionary *)plist;
    // Use plist
}
```

### 4. Check File Readability

```objective-c
// Check if file exists and is readable
if ([PPFileHelper isFileReadable:@"/path/to/file"]) {
    // File can be read
} else {
    // File doesn't exist or not readable
}
```

### 5. Get Error Description

```objective-c
NSError *error = nil;
NSData *data = [NSData dataWithContentsOfFile:path options:0 error:&error];
if (error) {
    NSString *description = [PPFileHelper descriptionForFileError:error];
    NSLog(@"%@", description);
}
```

## Behavior

### Returns `nil` for:
- File doesn't exist
- File exists but is not readable
- Permission denied error (NSFileReadNoPermissionError)
- Any other read error (after logging)

### Logs only:
- Non-permission file errors (for debugging)
- Plist parsing errors
- Does NOT log permission errors (expected behavior)

### Safe for:
- System-protected files
- User-restricted files
- Missing files
- Concurrent file operations
- All iOS/macOS versions

## Error Handling

The helper provides descriptive messages for common file errors:

```objective-c
typedef enum {
    NSFileReadNoPermissionError = 257,      // Permission denied
    NSFileNoSuchFileError = 260,            // File not found
    NSFileReadInvalidFileNameError = 261,   // Invalid filename
    NSFileReadCorruptFileError = 262,       // Corrupted file
    NSFileReadUnknownError = 256            // Unknown error
} NSFileErrorCode;
```

## Example: Safely Reading a Configuration File

```objective-c
// Instead of this (risky):
NSError *error = nil;
NSDictionary *config = [NSDictionary dictionaryWithContentsOfFile:configPath];
if (!config) {
    NSLog(@"Failed to read config: %@", error);  // May crash on permission error
}

// Use this (safe):
NSDictionary *config = (NSDictionary *)[PPFileHelper safePlistFromFile:configPath];
if (config) {
    NSString *value = config[@"key"];
} else {
    // File doesn't exist or permission denied (handled gracefully)
    [self useDefaultConfig];
}
```

## Implementation Notes

- Uses `NSDataReadingMappedIfSafe` for efficient memory-mapped file reading
- Supports multiple string encodings (UTF-8, ISO-Latin1)
- Minimizes logging to reduce console noise
- Thread-safe for concurrent access
- No external dependencies

## Files

- `PPFileHelper.h` - Header with public API
- `PPFileHelper.m` - Implementation
- Automatically included via `PrefixHeader.pch`

## Related Classes

- `NSFileManager` - For file system operations
- `NSData` - For binary file contents
- `NSPropertyListSerialization` - For plist parsing

---

**Created:** February 2026
**Purpose:** Safe file I/O with permission error handling
