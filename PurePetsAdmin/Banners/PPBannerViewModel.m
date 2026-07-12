//
//  PPBannerViewModel.m
//  PurePets
//

@import Firebase;
@import FirebaseAuth;
@import FirebaseMessaging;
@import FirebaseAuth;
#import "PPBannerViewModel.h"
@import Firebase;
@import FirebaseAuth;
@implementation PPBannerViewModel

#pragma mark - Designated Initializer

- (instancetype)initWithTitleEn:(NSString *)titleEn
                        titleAr:(NSString *)titleAr
                     descTextEn:(NSString *)descEn
                     descTextAr:(NSString *)descAr
                       postDate:(NSDate * _Nullable)postDate
              backgroundImageURL:(NSURL * _Nullable)bgURL
                  sampleImageURL:(NSURL * _Nullable)sampleURL
                   badgeImageURL:(NSURL * _Nullable)badgeURL
                     onTapAction:(PPBannerOnTapAction)action
                      textStyle:(PPBannerTextStyle)textStyle
                      onTapValue:(NSString * _Nullable)value
                        bannerID:(NSString *)bannerID {
    if (self = [super init]) {
        _titleTextEn      = [titleEn copy];
        _titleTextAr      = [titleAr copy];
        _descTextEn       = [descEn copy];
        _descTextAr       = [descAr copy];

        if (postDate) {
            _postDate = postDate;
            NSDateFormatter *fmt = [[NSDateFormatter alloc] init];
            [fmt setDateStyle:NSDateFormatterMediumStyle];
            [fmt setTimeStyle:NSDateFormatterNoStyle];
            _postDateText = [fmt stringFromDate:postDate];
        } else {
            _postDate = nil;
            _postDateText = @"";
        }

        _backgroundImageURL = [bgURL copy];
        _sampleImageURL     = [sampleURL copy];
        _badgeImageURL      = [badgeURL copy];

        _onTapAction    = action;
        _pannerTextStyle = textStyle;
        
        _onTapValue     = [value copy];
        _tapCount       = 0;
        _expirationDate = nil;
        _validityDuration = nil;
        _bannerID       = [bannerID copy];
    }
    return self;
}

#pragma mark - Convenience Initializers

- (instancetype)initWithTitle:(NSString *)title
                  description:(NSString *)desc
                     postDate:(NSString *)postDateText
            backgroundImageURL:(NSURL *)bgURL
                sampleImageURL:(NSURL *)sampleURL
                 badgeImageURL:(NSURL *)badgeURL {
    return [self initWithTitleEn:title
                         titleAr:@""
                      descTextEn:desc
                      descTextAr:@""
                        postDate:nil
               backgroundImageURL:bgURL
                   sampleImageURL:sampleURL
                    badgeImageURL:badgeURL
                      onTapAction:PPBannerOnTapViewAccessory
                       textStyle:PPBannerTextStyleBlack
                       onTapValue:nil
                         bannerID:@""];
}

- (instancetype)init {
    return [self initWithTitleEn:@""
                         titleAr:@""
                      descTextEn:@""
                      descTextAr:@""
                        postDate:nil
               backgroundImageURL:nil
                   sampleImageURL:nil
                    badgeImageURL:nil
                      onTapAction:PPBannerOnTapViewAccessory
                       textStyle:PPBannerTextStyleBlack
                       onTapValue:nil
                         bannerID:@""];
}






#pragma mark - Init from Firestore Dictionary
- (instancetype)initWithDictionary:(NSDictionary *)dict {
    NSString *bannerID    = dict[@"ChildsPannerID"] ?: dict[@"ChildBannerID"] ?: @"";
    NSString *titleEn     = dict[@"titleTextEn"] ?: @"";
    NSString *titleAr     = dict[@"titleTextAr"] ?: @"";
    NSString *descEn      = dict[@"descTextEn"] ?: @"";
    NSString *descAr      = dict[@"descTextAr"] ?: @"";

    NSDate *postDate =  [PPBannerViewModel dateFromAny:dict[@"postDate"]];
   
  
    

    NSURL *bgURL = dict[@"backgroundImageURL"] ? [NSURL URLWithString:dict[@"backgroundImageURL"]] : nil;
    NSURL *sampleURL = dict[@"sampleImageURL"] ? [NSURL URLWithString:dict[@"sampleImageURL"]] : nil;
    NSURL *badgeURL = dict[@"badgeImageURL"] ? [NSURL URLWithString:dict[@"badgeImageURL"]] : nil;

    PPBannerOnTapAction action = PPBannerOnTapViewAccessory;
    if ([dict[@"pannerOnTapAction"] isKindOfClass:[NSNumber class]]) {
        action = (PPBannerOnTapAction)[dict[@"pannerOnTapAction"] integerValue];
    }

    PPBannerTextStyle textStyle = [dict[@"pannerTextStyle"] integerValue];
    NSString *tapValue = dict[@"pannerOnTapValue"] ?: @"";

    if (self = [self initWithTitleEn:titleEn
                             titleAr:titleAr
                          descTextEn:descEn
                          descTextAr:descAr
                            postDate:postDate
                   backgroundImageURL:bgURL
                       sampleImageURL:sampleURL
                        badgeImageURL:badgeURL
                          onTapAction:action
                           textStyle:textStyle
                           onTapValue:tapValue
                             bannerID:bannerID]) {
        _tapCount = [dict[@"pannerTapsCount"] integerValue];

        if ([dict[@"expireInDateTime"] isKindOfClass:[NSDate class]]) {
            _expirationDate = [PPBannerViewModel dateFromAny:dict[@"expireInDateTime"]];
        }
    }
    return self;
}

#pragma mark - Helpers

- (NSString *)localizedTitleText {
    if (Language.languageVal == 1 && _titleTextAr.length > 0) {
        return _titleTextAr;
    }
    return _titleTextEn;
}

- (NSString *)localizedDescText {
    if (Language.languageVal == 1 && _descTextAr.length > 0) {
        return _descTextAr;
    }
    return _descTextEn;
}

- (BOOL)isExpired {
    if (!_expirationDate) return NO;
    return ([[NSDate date] timeIntervalSinceDate:_expirationDate] > 0);
}

- (NSString *)countdownTimeRemaining {
    if (!_expirationDate) return nil;

    NSDate *now = [NSDate date];
    if ([now timeIntervalSinceDate:_expirationDate] >= 0) return @"0m";

    NSCalendar *cal = [NSCalendar currentCalendar];
    NSUInteger units = NSCalendarUnitDay | NSCalendarUnitHour | NSCalendarUnitMinute;
    NSDateComponents *diff = [cal components:units fromDate:now toDate:_expirationDate options:0];

    NSMutableString *result = [NSMutableString string];
    if (diff.day > 0)   [result appendFormat:@"%ldd ", (long)diff.day];
    if (diff.hour >= 0) [result appendFormat:@"%ldh ", (long)diff.hour];
    if (diff.minute >= 0) [result appendFormat:@"%ldm", (long)diff.minute];
    return [result stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
}


- (NSDictionary *)toDictionary {
    return @{
        @"ChildsPannerID"   : PPSafeString(self.bannerID),
        @"titleTextEn"      : PPSafeString(self.titleTextEn),
        @"titleTextAr"      : PPSafeString(self.titleTextAr),
        @"descTextEn"       : PPSafeString(self.descTextEn),
        @"descTextAr"       : PPSafeString(self.descTextAr),
        @"postDate"         : self.postDate ?: [NSNull null],
        @"postDateText"     : PPSafeString(self.postDateText),
        @"backgroundImageURL": PPSafeString(self.backgroundImageURL.absoluteString),
        @"sampleImageURL"   : PPSafeString(self.sampleImageURL.absoluteString),
        @"badgeImageURL"    : PPSafeString(self.badgeImageURL.absoluteString),
        @"pannerOnTapAction": @(self.onTapAction),
        @"pannerTextStyle"  : @(self.pannerTextStyle),
        @"pannerOnTapValue" : PPSafeString(self.onTapValue),
        @"pannerTapsCount"  : @(self.tapCount),
        @"expireInDateTime" : self.expirationDate ?: [NSNull null],
        @"pannerValidity"   : self.validityDuration ? [NSString stringWithFormat:@"%ldd %ldh %ldm",
                                                       (long)self.validityDuration.day,
                                                       (long)self.validityDuration.hour,
                                                       (long)self.validityDuration.minute] : @""
    };
}

+ (NSDate *)dateFromAny:(id)field {
    if ([field isKindOfClass:[NSDate class]]) {
        return field;
    } else if ([field isKindOfClass:[FIRTimestamp class]]) {
        return [(FIRTimestamp *)field dateValue];
    } else if ([field isKindOfClass:[NSNumber class]]) {
        return [NSDate dateWithTimeIntervalSince1970:[field doubleValue]];
    } else if ([field isKindOfClass:[NSString class]]) {
        // Attempt ISO8601 parsing
        NSDateFormatter *fmt = [NSDateFormatter new];
        fmt.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
        fmt.dateFormat = @"yyyy-MM-dd'T'HH:mm:ssZ";
        return [fmt dateFromString:field];
    }
    return nil;
}
@end








/*//
//  PPBannerViewModel.m
//  PurePets
//

// PPBannerViewModel.m

#import "PPBannerViewModel.h"

@implementation PPBannerViewModel

- (instancetype)initWithTitle:(NSString *)title
                  description:(NSString *)desc
                     postDate:(NSString *)postDateText
            backgroundImageURL:(NSURL *)bgURL
                sampleImageURL:(NSURL *)sampleURL
                 badgeImageURL:(NSURL *)badgeURL {
    if (self = [super init]) {
        // Initialize with provided values (assume single language usage)
        _titleTextEn      = [title copy];
        _titleTextAr      = @"";            // default empty if not provided
        _descTextEn       = [desc copy];
        _descTextAr       = @"";
        _postDateText     = [postDateText copy];
        _backgroundImageURL = [bgURL copy];
        _sampleImageURL     = [sampleURL copy];
        _badgeImageURL      = [badgeURL copy];
        _postDate        = nil;
        _onTapAction     = PPBannerOnTapViewAccessory;  // default action
        _pannerTextStyle     = PPBannerTextStyleBlack;  // default action
        _onTapValue      = nil;
        _tapCount        = 0;
        _expirationDate  = nil;
        _validityDuration = nil;
        _bannerID        = @"";  // will be set if available
    }
    return self;
}

// Extended initializer that covers all properties
- (instancetype)initWithTitleEn:(NSString *)titleEn
                        titleAr:(NSString *)titleAr
                     descTextEn:(NSString *)descEn
                     descTextAr:(NSString *)descAr
                       postDate:(NSDate * _Nullable)postDate
              backgroundImageURL:(NSURL * _Nullable)bgURL
                  sampleImageURL:(NSURL * _Nullable)sampleURL
                   badgeImageURL:(NSURL * _Nullable)badgeURL
                     onTapAction:(PPBannerOnTapAction)action
                      textStyle:(PPBannerTextStyle)textStyle
                      onTapValue:(NSString * _Nullable)value
                        bannerID:(NSString *)bannerID {
    if (self = [super init]) {
        _titleTextEn      = [titleEn copy];
        _titleTextAr      = [titleAr copy];
        _descTextEn       = [descEn copy];
        _descTextAr       = [descAr copy];
        if (postDate) {
            _postDate = postDate;
            // Format the date into a user-facing string (e.g., "Sep 7, 2025")
            NSDateFormatter *fmt = [[NSDateFormatter alloc] init];
            [fmt setDateStyle:NSDateFormatterMediumStyle];
            [fmt setTimeStyle:NSDateFormatterNoStyle];
            _postDateText = [fmt stringFromDate:postDate];
        } else {
            _postDate = nil;
            _postDateText = @"";
        }
        _backgroundImageURL = [bgURL copy];
        _sampleImageURL     = [sampleURL copy];
        _badgeImageURL      = [badgeURL copy];
        _onTapAction     = action;
        _pannerTextStyle     = textStyle;
        _onTapValue      = [value copy];
        _tapCount        = 0;
        _expirationDate  = nil;
        _validityDuration = nil;
        _bannerID        = [bannerID copy];
    }
    return self;
}

// Fallback default init funnels to designated initializer
- (instancetype)init {
    return [self initWithTitle:@""
                   description:@""
                      postDate:@""
             backgroundImageURL:nil
                 sampleImageURL:nil
                  badgeImageURL:nil];
}

// Initialize from Firestore dictionary (child banner data)
- (instancetype)initWithDictionary:(NSDictionary *)dict {
    // Extract fields from the dictionary safely
    NSString *bannerID    = dict[@"ChildsPannerID"] ?: dict[@"ChildBannerID"] ?: @"";
    NSString *titleEn     = dict[@"titleTextEn"] ?: @"";
    NSString *titleAr     = dict[@"titleTextAr"] ?: @"";
    NSString *descEn      = dict[@"descTextEn"] ?: @"";
    NSString *descAr      = dict[@"descTextAr"] ?: @"";
    NSString *postDateStr = dict[@"postDate"] ?: @"";  // could be a timestamp string
    NSDate *postDate = nil;
    if ([postDateStr isKindOfClass:[NSString class]] && postDateStr.length > 0) {
        // Attempt to parse date string if in a standard format, otherwise leave as nil
        NSDateFormatter *df = [[NSDateFormatter alloc] init];
        // (Assume ISO8601 or known format from server, here just try a generic)
        [df setDateFormat:@"yyyy-MM-dd'T'HH:mm:ssZZZZZ"];
        postDate = [df dateFromString:postDateStr];
    } else if ([dict[@"postDate"] isKindOfClass:[NSDate class]]) {
        postDate = dict[@"postDate"];
    }
    // URLs: assume stored as strings in Firestore
    NSURL *bgURL    = nil;
    NSURL *sampleURL= nil;
    NSURL *badgeURL = nil;
    if ([dict[@"backgroundImageURL"] isKindOfClass:[NSString class]]) {
        bgURL = [NSURL URLWithString:dict[@"backgroundImageURL"]];
    }
    if ([dict[@"sampleImageURL"] isKindOfClass:[NSString class]]) {
        sampleURL = [NSURL URLWithString:dict[@"sampleImageURL"]];
    }
    if ([dict[@"badgeImageURL"] isKindOfClass:[NSString class]]) {
        badgeURL = [NSURL URLWithString:dict[@"badgeImageURL"]];
    }
    PPBannerOnTapAction action = PPBannerOnTapViewAccessory;
    if (dict[@"pannerOnTapAction"] || dict[@"bannerOnTapAction"]) {
        // Get the numeric action or map string to enum
        id actionField = dict[@"pannerOnTapAction"] ?: dict[@"bannerOnTapAction"];
        if ([actionField isKindOfClass:[NSNumber class]]) {
            action = (PPBannerOnTapAction)[actionField integerValue];
        } else if ([actionField isKindOfClass:[NSString class]]) {
            NSString *actionStr = (NSString *)actionField;
            if ([actionStr isEqualToString:@"PPBannerOnTapViewAccessory"]) {
                action = PPBannerOnTapViewAccessory;
            } else if ([actionStr isEqualToString:@"PPBannerOnTapViewAd"]) {
                action = PPBannerOnTapViewAd;
            } else if ([actionStr isEqualToString:@"PPBannerOnTapOpenUrl"]) {
                action = PPBannerOnTapOpenUrl;
            } else if ([actionStr isEqualToString:@"PPBannerOnTapCallPhoneNumber"]) {
                action = PPBannerOnTapCallPhoneNumber;
            } else if ([actionStr isEqualToString:@"PPBannerOnTapWhatsApp"]) {
                action = PPBannerOnTapWhatsApp;
            }
        }
    }
    NSUInteger pannerTextStyle      = [dict[@"pannerTextStyle"] interval];
    NSString *tapValue = dict[@"pannerOnTapValue"] ?: dict[@"bannerOnTapValue"] ?: @"";
    NSNumber *taps = dict[@"pannerTapsCount"] ?: dict[@"bannerTapsCount"] ?: @(0);
    NSUInteger tapCount = [taps unsignedIntegerValue];
    // Validity and expiration
    NSDate *expires = nil;
    if (dict[@"expireInDateTime"]) {
        // Firestore timestamp might come as an NSDate or seconds.
        if ([dict[@"expireInDateTime"] isKindOfClass:[NSDate class]]) {
            expires = dict[@"expireInDateTime"];
        } else if ([dict[@"expireInDateTime"] isKindOfClass:[NSNumber class]]) {
            // If it's a timestamp in seconds
            NSTimeInterval ts = [dict[@"expireInDateTime"] doubleValue];
            expires = [NSDate dateWithTimeIntervalSince1970:ts];
        } else if ([dict[@"expireInDateTime"] isKindOfClass:[NSString class]]) {
            // Try parsing string timestamp
            NSDateFormatter *df = [[NSDateFormatter alloc] init];
            [df setDateFormat:@"yyyy-MM-dd'T'HH:mm:ssZZZZZ"];
            expires = [df dateFromString:dict[@"expireInDateTime"]];
        }
    }
    NSDateComponents *validity = nil;
    if (dict[@"pannerValidity"] || dict[@"validateDaysHoursMins"]) {
        // If admin provided a validity duration, parse it (could be in a custom format, e.g. "5d3h20m")
        NSString *valStr = dict[@"pannerValidity"] ?: dict[@"validateDaysHoursMins"];
        if ([valStr isKindOfClass:[NSString class]] && valStr.length > 0) {
            validity = [[NSDateComponents alloc] init];
            // Simple parse example: assume format "Xd Yh Zm"
            NSScanner *scanner = [NSScanner scannerWithString:valStr];
            NSInteger days, hours, mins;
            days = hours = mins = 0;
            if ([scanner scanInteger:&days]) { validity.day = days; }
            [scanner scanUpToString:@"h" intoString:NULL]; // skip to hours part
            if ([scanner scanInteger:&hours]) { validity.hour = hours; }
            [scanner scanUpToString:@"m" intoString:NULL]; // skip to mins part
            if ([scanner scanInteger:&mins]) { validity.minute = mins; }
        }
    }
    // Initialize with the gathered values
    if (self = [self initWithTitleEn:titleEn
                             titleAr:titleAr
                          descTextEn:descEn
                          descTextAr:descAr
                            postDate:postDate
                   backgroundImageURL:bgURL
                       sampleImageURL:sampleURL
                        badgeImageURL:badgeURL
                          onTapAction:action
                           onTapValue:tapValue
                      pannerTextStyle:pannerTextStyle
                             bannerID:bannerID]) {
        _tapCount = tapCount;
        _expirationDate = expires;
        _validityDuration = validity;
    }
    return self;
}

// Get the appropriate title based on the current locale or app language setting.
- (NSString *)localizedTitleText {
    if (Language.languageVal == 1 && _titleTextAr.length > 0) {
        return _titleTextAr;
    }
    return _titleTextEn;
}

// Similarly for description text.
- (NSString *)localizedDescText {
    if (Language.languageVal == 1 && _descTextAr.length > 0) {
        return _descTextAr;
    }
    return _descTextEn;
}

// Check if the banner is expired (current time past expirationDate).
- (BOOL)isExpired {
    if (!_expirationDate) {
        return NO;
    }
    return ([[NSDate date] timeIntervalSinceDate:_expirationDate] > 0);
}

// Compute remaining time as a formatted string (days, hours, minutes).
- (NSString *)countdownTimeRemaining {
    if (!_expirationDate) {
        // If no specific expiration date, but maybe a validity duration is set:
        if (_validityDuration) {
            // Compute expiration by adding duration to postDate or current date
            NSDate *startDate = _postDate ? _postDate : [NSDate date];
            NSCalendar *cal = [NSCalendar currentCalendar];
            NSDate *calcExpire = [cal dateByAddingComponents:_validityDuration toDate:startDate options:0];
            self.expirationDate = calcExpire; // update expirationDate for consistency
        } else {
            return nil;
        }
    }
    // Now _expirationDate is set
    NSDate *now = [NSDate date];
    if ([now timeIntervalSinceDate:_expirationDate] >= 0) {
        return @"0m"; // already expired or expiring now
    }
    // Calculate difference
    NSCalendar *cal = [NSCalendar currentCalendar];
    NSUInteger units = NSCalendarUnitDay | NSCalendarUnitHour | NSCalendarUnitMinute;
    NSDateComponents *diff = [cal components:units fromDate:now toDate:_expirationDate options:0];
    NSInteger days = diff.day;
    NSInteger hours = diff.hour;
    NSInteger mins = diff.minute;
    // Format to a string, e.g. "2d 5h 30m"
    NSMutableString *result = [NSMutableString string];
    if (days > 0) {
        [result appendFormat:@"%ldd ", (long)days];
    }
    if (hours >= 0) {
        [result appendFormat:@"%ldh ", (long)hours];
    }
    if (mins >= 0) {
        [result appendFormat:@"%ldm", (long)mins];
    }
    return [result stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
}

@end
*/
