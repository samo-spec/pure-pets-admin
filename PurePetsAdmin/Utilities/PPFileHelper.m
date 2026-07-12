//
//  PPFileHelper.m
//  PurePetsAdmin
//
//  Safe file I/O utilities with proper error handling
//

#import "PPFileHelper.h"

@implementation PPFileHelper

#pragma mark - Safe File Reading

+ (nullable NSData *)safeDataFromFile:(NSString *)path {
    if (!path || path.length == 0) {
        return nil;
    }
    
    NSFileManager *fm = [NSFileManager defaultManager];
    
    // Check if file exists
    if (![fm fileExistsAtPath:path]) {
        return nil;
    }
    
    // Check if file is readable
    if (![fm isReadableFileAtPath:path]) {
        return nil;
    }
    
    NSError *error = nil;
    NSData *data = [NSData dataWithContentsOfFile:path
                                          options:NSDataReadingMappedIfSafe
                                            error:&error];
    
    if (!data && error) {
        // Only log non-permission errors
        if (![error.domain isEqualToString:NSCocoaErrorDomain] ||
            error.code != NSFileReadNoPermissionError) {
            NSLog(@"[PPFileHelper] Failed to read file '%@': %@ (code %ld)",
                  path.lastPathComponent,
                  error.localizedDescription,
                  (long)error.code);
        }
        return nil;
    }
    
    return data;
}

+ (nullable NSString *)safeStringFromFile:(NSString *)path {
    NSData *data = [self safeDataFromFile:path];
    if (!data) {
        return nil;
    }
    
    NSString *string = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    if (!string) {
        // Try with other common encodings
        string = [[NSString alloc] initWithData:data encoding:NSISOLatin1StringEncoding];
    }
    
    return string;
}

+ (nullable id)safePlistFromFile:(NSString *)path {
    NSData *data = [self safeDataFromFile:path];
    if (!data) {
        return nil;
    }
    
    NSError *error = nil;
    id plist = [NSPropertyListSerialization propertyListWithData:data
                                                          options:NSPropertyListImmutable
                                                           format:NULL
                                                            error:&error];
    
    if (!plist && error) {
        NSLog(@"[PPFileHelper] Failed to parse plist '%@': %@",
              path.lastPathComponent,
              error.localizedDescription);
        return nil;
    }
    
    return plist;
}

#pragma mark - File Access Checking

+ (BOOL)isFileReadable:(NSString *)path {
    if (!path || path.length == 0) {
        return NO;
    }
    
    NSFileManager *fm = [NSFileManager defaultManager];
    return [fm fileExistsAtPath:path] && [fm isReadableFileAtPath:path];
}

#pragma mark - Error Description

+ (NSString *)descriptionForFileError:(NSError *)error {
    if (!error) {
        return @"Unknown error";
    }
    
    // Check for specific error codes
    if ([error.domain isEqualToString:NSCocoaErrorDomain]) {
        switch (error.code) {
            case NSFileReadNoPermissionError:
                return @"Permission denied: The file cannot be read due to insufficient permissions.";
            case NSFileNoSuchFileError:
                return @"File not found: The specified file does not exist.";
            case NSFileReadInvalidFileNameError:
                return @"Invalid file name: The file name contains invalid characters.";
            case NSFileReadCorruptFileError:
                return @"Corrupt file: The file appears to be corrupted or invalid.";
            case NSFileReadUnknownError:
                return @"Unknown read error: An unknown error occurred while reading the file.";
            default:
                return [NSString stringWithFormat:@"File error (code %ld): %@",
                        (long)error.code,
                        error.localizedDescription];
        }
    }
    
    // Default to the error's localized description
    return error.localizedDescription ?: @"An unknown file error occurred.";
}

@end
