//
//  PPFileHelper.h
//  PurePetsAdmin
//
//  Safe file I/O utilities with proper error handling
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/**
 Safe file reading utilities that handle permission errors gracefully.
 These helpers prevent crashes when attempting to read system-protected files
 or files with restricted access permissions.
 */
@interface PPFileHelper : NSObject

/**
 Safely read file contents as NSData.
 
 Returns nil if:
 - File doesn't exist
 - File is not readable (permission denied)
 - Any other read error occurs
 
 Logs other errors (non-permission) for debugging.
 
 @param path The file path to read
 @return File contents as NSData, or nil if unreadable
 */
+ (nullable NSData *)safeDataFromFile:(NSString *)path;

/**
 Safely read file contents as a string.
 
 Returns nil if file cannot be read or decoded as UTF-8.
 
 @param path The file path to read
 @return File contents as NSString, or nil if unreadable
 */
+ (nullable NSString *)safeStringFromFile:(NSString *)path;

/**
 Safely read a plist file.
 
 Returns nil if file cannot be read or parsed as a plist.
 
 @param path The plist file path to read
 @return Parsed plist object (dict/array/etc), or nil if unreadable
 */
+ (nullable id)safePlistFromFile:(NSString *)path;

/**
 Check if a file is readable by the current process.
 
 @param path The file path to check
 @return YES if file exists and is readable, NO otherwise
 */
+ (BOOL)isFileReadable:(NSString *)path;

/**
 Get a user-friendly error message for file read failures.
 
 @param error The NSError from a failed file operation
 @return A human-readable error description
 */
+ (NSString *)descriptionForFileError:(NSError *)error;

@end

NS_ASSUME_NONNULL_END
