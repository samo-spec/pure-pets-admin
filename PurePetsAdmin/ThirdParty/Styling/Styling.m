//
//  Styling.m
//  PurePetsAdmin
//

#import "Styling.h"
#import "Lottie.h"
#import "AppManager.h" // for kAppPrimaryColor, etc.
@import Firebase;
@import FirebaseAuth;
@import FirebaseMessaging;
@import FirebaseAuth;

@implementation Styling

#pragma mark - Generic Methods
+ (void)applyStyleWithCornerRadius:(CGFloat)cornerRadius
                     backgroundColor:(UIColor *)backgroundColor
                         borderColor:(nullable UIColor *)borderColor
                         borderWidth:(CGFloat)borderWidth
                           addShadow:(BOOL)addShadow
                              toView:(UIView *)view
{
    // 🔹 Apply rounded corners
    if(cornerRadius > 0)
        view.clipsToBounds = YES;
    view.layer.cornerRadius = cornerRadius;

    // 🔹 Background color
    view.backgroundColor = backgroundColor;

    // 🔹 Border color and width
    if (borderColor) {
        view.layer.borderColor = borderColor.CGColor;
        view.layer.borderWidth = borderWidth;
    } else {
        view.layer.borderWidth = 0;
        view.layer.borderColor = nil;
    }

    // 🔹 Optional shadow
    if (addShadow) {
        view.layer.shadowColor = [UIColor colorWithWhite:0 alpha:0.25].CGColor;
        view.layer.shadowOpacity = 0.2;
        view.layer.shadowRadius = 4.0;
        view.layer.shadowOffset = CGSizeMake(0, 3);
        view.layer.masksToBounds = NO;
        DLog(@"[Styling] Shadow applied to %@", view);
    } else {
        view.layer.shadowOpacity = 0.0;
        DLog(@"[Styling] Shadow removed from %@", view);
    }
}

+ (void)applyStyleWithCornerRadius:(CGFloat)cornerRadius
                        borderColor:(nullable UIColor *)borderColor
                          addShadow:(BOOL)addShadow
                             toView:(UIView *)view
{
    [self applyStyleWithCornerRadius:cornerRadius
                      backgroundColor:UIColor.clearColor
                          borderColor:borderColor
                          borderWidth:(borderColor ? 1.0 : 0.0)
                            addShadow:addShadow
                               toView:view];
    DLog(@"[Styling] Short style method used for %@", view);
}

#pragma mark - Presets
+ (void)applyCardStyleToView:(UIView *)view {
    [self applyStyleWithCornerRadius:12
                      backgroundColor:UIColor.whiteColor
                          borderColor:nil
                          borderWidth:0
                            addShadow:YES
                               toView:view];
    DLog(@"[Styling] Card style applied");
}

+ (void)applyIconButtonStyle:(UIButton *)button
                   tintColor:(UIColor *)tintColor
             backgroundColor:(UIColor *)backgroundColor {
    if (!button) return;
    
    // Force layout so button has a real size
    [button layoutIfNeeded];
    
    button.tintColor = tintColor;
    button.backgroundColor = backgroundColor;
    
    // ✅ Round based on current bounds
    CGFloat radius = button.hxh / 2; ;
    button.layer.cornerRadius = radius;
    button.clipsToBounds = YES;
    button.layer.masksToBounds = NO; // allow shadow
    
    // Shadow (if needed)
    button.layer.shadowColor = [UIColor blackColor].CGColor;
    button.layer.shadowOpacity = 0.07f;
    button.layer.shadowOffset = CGSizeMake(0, 2);
    button.layer.shadowRadius = 4.0f;
    
   // DLog(@"[Styling] Icon button corner radius %.2f applied", radius);
}




+ (void)applyHeaderStyleToView:(UIView *)view {
    [self applyStyleWithCornerRadius:0
                      backgroundColor:AppBackgroundClr
                          borderColor:nil
                          borderWidth:0
                            addShadow:NO
                               toView:view];
    DLog(@"[Styling] Header style applied");
}


+ (UIFont *)fontBold:(CGFloat)size {
    UIFont *font = [UIFont fontWithName:@"Beiruti-Bold" size:size];
    return font ?: [UIFont boldSystemFontOfSize:size]; // fallback
}

+ (UIFont *)fontMedium:(CGFloat)size {
    UIFont *font = [UIFont fontWithName:@"Beiruti-Medium" size:size];
    return font ?: [UIFont systemFontOfSize:size weight:UIFontWeightMedium]; // fallback
}

+ (UIFont *)fontRegular:(CGFloat)size {
    UIFont *font = [UIFont fontWithName:@"Beiruti-Regular" size:size];
    return font ?: [UIFont systemFontOfSize:size]; // fallback
}


+ (void)applyButtonTextStyle:(UIButton *)button
                        size:(CGFloat)pointSize
                      weight:(UIFontWeight)weight
                       scale:(UIFontTextStyle)scale
{
    if (!button) return;

    // Create base font
    UIFont *baseFont = [UIFont systemFontOfSize:pointSize weight:weight];

    // Apply dynamic scaling (so it respects Accessibility > Larger Text)
    UIFontMetrics *metrics = [UIFontMetrics metricsForTextStyle:scale];
    UIFont *scaledFont = [metrics scaledFontForFont:baseFont];

    // Apply to button title
    button.titleLabel.font = scaledFont;
    button.titleLabel.adjustsFontForContentSizeCategory = YES;

    DLog(@"[Styling] Applied button font size %.1f, weight %.1f, scale %@",
         pointSize, weight, scale);
}

+ (void)applyButtonIconStyle:(UIButton *)button
                   tintColor:(UIColor *)tintColor
             backgroundColor:(UIColor *)backgroundColor
                cornerRadius:(CGFloat)cornerRadius
            symbolPointSize:(CGFloat)pointSize
                     weight:(UIImageSymbolWeight)weight
                      scale:(UIImageSymbolScale)scale
{
    if (!button) return;

    // 🎨 Colors
    button.tintColor = tintColor ?: UIColor.whiteColor;
    button.backgroundColor = backgroundColor ?: UIColor.clearColor;

    
    // ⚡️ Detect if current image is SF Symbol (systemName based)
    UIImage *icon = [button imageForState:UIControlStateNormal];
    if (icon && icon.configuration) {
        // Apply SF Symbol config
        UIImageSymbolConfiguration *config =
        [UIImageSymbolConfiguration configurationWithPointSize:pointSize
                                                        weight:weight
                                                         scale:scale];
        [button setImage:[icon imageByApplyingSymbolConfiguration:config]
                forState:UIControlStateNormal];
        button.imageView.contentMode = UIViewContentModeScaleAspectFit;
        DLog(@"[Styling] Applied SF Symbol config (%.1f pt, weight %ld, scale %ld) ✅",
             pointSize, (long)weight, (long)scale);
    } else {
        DLog(@"[Styling] Normal image detected, skipping SF Symbol config ⚪️");
    }

    // 🟣 Apply rounded style after layout
    dispatch_async(dispatch_get_main_queue(), ^{
        CGFloat radius = cornerRadius > 0 ? cornerRadius :
                         MIN(button.bounds.size.width, button.bounds.size.height) / 2.0;
        button.layer.cornerRadius = radius;
        button.layer.masksToBounds = NO;

        DLog(@"[Styling] Icon button radius applied: %.1f", radius);
    });
}

+ (void)applyGroupCellStyle:(UITableViewCell *)cell
               atIndexPath:(NSIndexPath *)indexPath
                inTableView:(UITableView *)tableView {
    
    // Use insets to make cell look like a floating card
    CGFloat sideInset = 16;
    CGRect bounds = CGRectMake(sideInset, 8, tableView.bounds.size.width - sideInset * 2, cell.bounds.size.height - 8);
    
    // Always apply full rounded rect (card style)
    UIBezierPath *maskPath = [UIBezierPath bezierPathWithRoundedRect:bounds cornerRadius:20];
    
    // Mask
    CAShapeLayer *maskLayer = [CAShapeLayer layer];
    maskLayer.path = maskPath.CGPath;
    cell.layer.mask = maskLayer;
    
    // Remove old shadows
    for (CALayer *sublayer in cell.contentView.layer.sublayers.copy) {
        if ([sublayer.name isEqualToString:@"GroupCellShadow"]) {
            [sublayer removeFromSuperlayer];
        }
    }
    
    // Shadow layer
    CAShapeLayer *shadowLayer = [CAShapeLayer layer];
    shadowLayer.name = @"GroupCellShadow";
    shadowLayer.path = maskPath.CGPath;
    shadowLayer.fillColor = UIColor.whiteColor.CGColor; // AppForgroundColr if you want
    shadowLayer.frame = bounds;
    
    shadowLayer.shadowColor = [UIColor blackColor].CGColor;
    shadowLayer.shadowOpacity = 0.15;
    shadowLayer.shadowOffset = CGSizeMake(0, 2);
    shadowLayer.shadowRadius = 6;
    
    [cell.contentView.layer insertSublayer:shadowLayer atIndex:0];
    
    // Make sure background is transparent
    cell.backgroundColor = UIColor.clearColor;
    cell.contentView.backgroundColor = UIColor.clearColor;
}




#pragma mark - Lottie Animation

+ (void)setAnimationNamed:(NSString *)fileName
                   toView:(LOTAnimationView *)lot
                withSpeed:(float)animationSpeed
               completion:(void (^)(BOOL success))completion
{
    [Styling fetchLottieJSONFromFirebasePath:[NSString stringWithFormat:@"LottieAnimations/%@.json", fileName]
                                  completion:^(NSDictionary * _Nonnull jsonDict, NSError * _Nonnull error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (error) {
                NSLog(@"❌ Lottie: Failed to fetch JSON: %@", error.localizedDescription);
                if (completion) completion(NO);
                return;
            }

            LOTComposition *composition = [LOTComposition animationFromJSON:jsonDict];
            if (!composition) {
                NSLog(@"❌ Lottie: Failed to build LOTComposition");
                if (completion) completion(NO);
                return;
            }

            // Apply composition
            [lot setSceneModel:composition];
            lot.animationSpeed = animationSpeed;
            lot.loopAnimation  = YES;
            lot.hidden         = NO;

            // Prepare for a smooth reveal
            lot.alpha = 0.0;
            lot.transform = CGAffineTransformMakeScale(0.96, 0.96);

            // Start playing immediately
            [lot play];

            // Fade + gentle pop-in
            [UIView animateWithDuration:0.35
                                  delay:0
                 usingSpringWithDamping:0.90
                  initialSpringVelocity:0.20
                                options:UIViewAnimationOptionCurveEaseOut
                             animations:^{
                                 lot.alpha = 1.0;
                                 lot.transform = CGAffineTransformIdentity;
                             }
                             completion:nil];

            if (completion) completion(YES);
        });
    }];

}

+ (void)fetchLottieJSONFromFirebasePath:(NSString *)storagePath
                             completion:(void (^)(NSDictionary *jsonDict, NSError *error))completion {

    static YYCache *cache = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        cache = [[YYCache alloc] initWithName:@"LottieJSONCache"];
    });
   
    NSString *cacheKey = [NSString stringWithFormat:@"lottie_%@", storagePath];

    // 🔹 Cached?
    NSDictionary *cachedJSON = (NSDictionary *)[cache objectForKey:cacheKey];
    if (cachedJSON) {
        NSLog(@"✅ Lottie: Loaded from cache");
        if (completion) completion(cachedJSON, nil);
        return;
    }

    // 🔹 Download from Firebase
    FIRStorage *storage = [FIRStorage storage];
    FIRStorageReference *ref = [storage referenceWithPath:storagePath];

    int64_t maxDownloadSize = 20 * 1024 * 1024; // 20 MB

    [ref dataWithMaxSize:maxDownloadSize completion:^(NSData * _Nullable data, NSError * _Nullable error) {
        if (error || !data) {
            if (completion) completion(nil, error ?: [NSError errorWithDomain:@"LottieFetch" code:-1 userInfo:nil]);
            return;
        }

        NSString *lower = storagePath.lowercaseString;
        BOOL isDotLottie = [lower hasSuffix:@".lottie"];

        if (!isDotLottie) {
            // JSON only
            NSError *jsonErr = nil;
            NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data options:kNilOptions error:&jsonErr];
            if (jsonErr || ![json isKindOfClass:[NSDictionary class]]) {
                if (completion) completion(nil, jsonErr);
                return;
            }
            [cache setObject:json forKey:cacheKey];
            if (completion) completion(json, nil);
            return;
        }

#if __has_include(<SSZipArchive/SSZipArchive.h>)
        // Handle .lottie
        NSString *tempDir = [NSTemporaryDirectory() stringByAppendingPathComponent:[[NSUUID UUID] UUIDString]];
        NSString *zipPath = [tempDir stringByAppendingPathComponent:@"anim.lottie"];

        NSError *fsErr = nil;
        [[NSFileManager defaultManager] createDirectoryAtPath:tempDir withIntermediateDirectories:YES attributes:nil error:&fsErr];
        if (![data writeToFile:zipPath options:NSDataWritingAtomic error:&fsErr]) {
            if (completion) completion(nil, fsErr);
            return;
        }

        NSString *unzipDir = [tempDir stringByAppendingPathComponent:@"unzipped"];
        if (![SSZipArchive unzipFileAtPath:zipPath toDestination:unzipDir]) {
            if (completion) completion(nil, [NSError errorWithDomain:@"LottieFetch" code:-2 userInfo:nil]);
            return;
        }

        NSString *manifestPath = [unzipDir stringByAppendingPathComponent:@"manifest.json"];
        NSData *manifestData = [NSData dataWithContentsOfFile:manifestPath];
        NSDictionary *manifest = manifestData ? [NSJSONSerialization JSONObjectWithData:manifestData options:0 error:nil] : nil;

        NSArray *anims = manifest[@"animations"];
        NSDictionary *chosen = anims.count ? anims.firstObject : nil;
        NSString *jsonRelPath = chosen[@"json"] ?: @"animations/animation.json";
        NSString *jsonAbsPath = [unzipDir stringByAppendingPathComponent:jsonRelPath];

        NSData *jsonData = [NSData dataWithContentsOfFile:jsonAbsPath];
        NSDictionary *json = jsonData ? [NSJSONSerialization JSONObjectWithData:jsonData options:0 error:nil] : nil;

        if (json) {
            [cache setObject:json forKey:cacheKey];
            if (completion) completion(json, nil);
        } else {
            if (completion) completion(nil, [NSError errorWithDomain:@"LottieFetch" code:-3 userInfo:nil]);
        }

        // Cleanup temp files
        dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
            [[NSFileManager defaultManager] removeItemAtPath:tempDir error:nil];
        });
#else
        if (completion) completion(nil, [NSError errorWithDomain:@"LottieFetch"
                                                           code:-9
                                                       userInfo:@{NSLocalizedDescriptionKey:
                                                                  @".lottie support requires SSZipArchive. Add `pod 'SSZipArchive'`"}]);
#endif
    }];
}


+ (void)setRowFonts:(XLFormRowDescriptor *)row
{
    row.cellConfig[@"textLabel.font"] = [Styling fontMedium:17];
    row.cellConfig[@"textField.font"] = [Styling fontMedium:17];
}

+ (void)setRowButtonStyle:(XLFormRowDescriptor *)row
{
    row.cellConfigAtConfigure[@"backgroundColor"] = AppPrimaryClr;
    row.cellConfigAtConfigure[@"textLabel.textColor"] = [UIColor whiteColor];
  //  row.cellConfigAtConfigure[@"layer.cornerRadius"] = @(10.0);
    row.cellConfigAtConfigure[@"layer.masksToBounds"] = @YES;
}


+ (void)setupFormAppearance {
    
    [[UILabel appearanceWhenContainedInInstancesOfClasses:@[[UITableViewCell class]]]
          setFont:[Styling fontMedium:15]];
    
    // ✅ Change detail font
   // [XLFormViewController.cellClassesForRowDescriptorTypes setObject:[PPXLFormImageCell class] forKey:@"PPXLFormImageCell"];
    [XLFormViewController.cellClassesForRowDescriptorTypes setObject:[RoleSummaryCell class] forKey:@"RoleSummaryPush"];
    [XLFormViewController.cellClassesForRowDescriptorTypes setObject:[XLAdminCell class] forKey:@"XLAdminCell"];
   // [XLFormViewController.cellClassesForRowDescriptorTypes setObject:[XLAdminCell class] forKey:@"XLFormRowXHPhotoViewBanner"];
    
    
    
    // HXPhotoSubViewCell appearance removed (HXPhotoPickerObjC replaced by PPImageCollection)
    
    // === XLForm TableView ===
    [[UITableView appearanceWhenContainedInInstancesOfClasses:@[[XLFormViewController class]]] setBackgroundColor:AppBackgroundClr];
    
    // === XLForm Cell Labels ===
    [[UILabel appearanceWhenContainedInInstancesOfClasses:@[[XLFormBaseCell class]]] setFont:[Styling fontMedium:15]];
    [[UILabel appearanceWhenContainedInInstancesOfClasses:@[[XLFormBaseCell class]]] setTextColor:SeconderyTextClr];
    
    // === XLForm TextField/TextView ===
    [[UITextField appearanceWhenContainedInInstancesOfClasses:@[[XLFormBaseCell class]]] setFont:[Styling fontMedium:15]];
    [[UITextField appearanceWhenContainedInInstancesOfClasses:@[[XLFormBaseCell class]]] setTextColor:PrimaryTextClr];
    
    [[UITextView appearanceWhenContainedInInstancesOfClasses:@[[XLFormBaseCell class]]] setFont:[Styling fontMedium:15]];
    [[UITextView appearanceWhenContainedInInstancesOfClasses:@[[XLFormBaseCell class]]] setTextColor:PrimaryTextClr];
}

+ (void)applyGlobalStyleToRow:(XLFormRowDescriptor *)row {
    UIFont *font = [Styling fontMedium:16];
    UIColor *textColor = PrimaryTextClr;
    UIColor *secondaryColor = SeconderyTextClr;

    // Always safe
    row.cellConfig[@"textLabel.font"] = font;
    row.cellConfig[@"textLabel.textColor"] = textColor;
    row.cellConfig[@"detailTextLabel.font"] = font;
    row.cellConfig[@"detailTextLabel.textColor"] = secondaryColor;

    // === Text-field based rows ===
    if ([row.rowType isEqualToString:XLFormRowDescriptorTypeText] ||
        [row.rowType isEqualToString:XLFormRowDescriptorTypeName] ||
        [row.rowType isEqualToString:XLFormRowDescriptorTypeEmail] ||
        [row.rowType isEqualToString:XLFormRowDescriptorTypeURL] ||
        [row.rowType isEqualToString:XLFormRowDescriptorTypePhone] ||
        [row.rowType isEqualToString:XLFormRowDescriptorTypePassword]) {
        row.cellConfig[@"textField.font"] = font;
        row.cellConfig[@"textField.textColor"] = textColor;
    }

    // === Multiline ===
    if ([row.rowType isEqualToString:XLFormRowDescriptorTypeTextView]) {
        row.cellConfig[@"textView.font"] = font;
        row.cellConfig[@"textView.textColor"] = textColor;
    }

    // === Buttons ===
    if ([row.rowType isEqualToString:XLFormRowDescriptorTypeButton]) {
        row.cellConfig[@"textLabel.textAlignment"] = @(NSTextAlignmentCenter);
        row.cellConfig[@"detailTextLabel.textColor"] = AppForgroundColr;
        row.cellConfig[@"textLabel.textColor"] = AppForgroundColr;
    }

    // === Segmented control ===
    if ([row.rowType isEqualToString:XLFormRowDescriptorTypeSelectorSegmentedControl]) {
        row.cellConfig[@"segmentedControl.tintColor"] = AppPrimaryClr;
        row.cellConfig[@"segmentedControl.backgroundColor"] = AppForgroundColr;
        row.cellConfig[@"segmentedControl.layer.cornerRadius"] = @8;
        row.cellConfig[@"segmentedControl.layer.masksToBounds"] = @YES;
    }

    // ✅ Apply RTL / LTR globally
    UISemanticContentAttribute attr = [Language semanticAttributeForCurrentLanguage];
    row.cellConfig[@"contentView.semanticContentAttribute"] = @(attr);
    row.cellConfig[@"textLabel.semanticContentAttribute"] = @(attr);
    row.cellConfig[@"detailTextLabel.semanticContentAttribute"] = @(attr);
}



+ (void)applyCorner:(CGFloat)cornerRadius
   backgroundColor:(UIColor *)backgroundColor
            toView:(UIView *)view
{
    if (!view) return;
    
    view.layer.cornerRadius = cornerRadius;
    view.layer.masksToBounds = YES;
    view.backgroundColor = backgroundColor ?: UIColor.clearColor;
    
    DLog(@"[Styling] Corner %.1f + BG color applied to %@", cornerRadius, view);
}


// Back-compat convenience
+ (void)applyBackgroundStyleForTableView:(UITableView *)tableView
                                   cell:(UITableViewCell *)cell
                              indexPath:(NSIndexPath *)indexPath
                          useRowCardMode:(BOOL)useRowCardMode
{
    [self applyBackgroundStyleForTableView:tableView
                                      cell:cell
                                 indexPath:indexPath
                             useRowCardMode:useRowCardMode
                           buttonRowIndex:-1
                             buttonSection:-1];
}

+ (void)applyBackgroundStyleForTableView:(UITableView *)tableView
                                   cell:(UITableViewCell *)cell
                              indexPath:(NSIndexPath *)indexPath
                          useRowCardMode:(BOOL)useRowCardMode
                        buttonRowIndex:(NSInteger)buttonRowIndex
                          buttonSection:(NSInteger)buttonSection
{
    // Clear defaults for card mode
    if (useRowCardMode) {
        cell.backgroundColor = UIColor.clearColor;
        cell.contentView.backgroundColor = UIColor.clearColor;
    }
    
    
    if(indexPath.row == buttonRowIndex && indexPath.section == buttonSection)
    {
        cell.backgroundColor = AppPrimaryClr;
        cell.contentView.backgroundColor = AppPrimaryClr;
        cell.tintColor  = AppForgroundColr;

    }
    else
    {
        cell.backgroundColor = AppForgroundColr;
        cell.contentView.backgroundColor = AppForgroundColr;
        cell.tintColor  = AppPrimaryClr;
    }
    cell.contentView.tintColor  = AppPrimaryClr;
    // Determine rounding based on position
    NSInteger rows = [tableView numberOfRowsInSection:indexPath.section];
    CGFloat radius = 26.0;
    CGRect bounds = cell.bounds; // willDisplayCell timing

    // Special “button” row (full rounding)
    BOOL isButtonRow = (buttonRowIndex >= 0 &&
                        indexPath.section == buttonSection &&
                        indexPath.row == buttonRowIndex);

    UIBezierPath *path = nil;

    if (isButtonRow) {
        path = [UIBezierPath bezierPathWithRoundedRect:bounds cornerRadius:radius];
        // Optional: tweak appearance for the button row only:
        // cell.contentView.backgroundColor = AppPrimaryClr;
        // cell.textLabel.textColor = UIColor.whiteColor;
        // tableView.separatorStyle = UITableViewCellSeparatorStyleNone;
    } else if (rows <= 1) {
        path = [UIBezierPath bezierPathWithRoundedRect:bounds cornerRadius:radius];
    } else if (indexPath.row == 0) {
        path = [UIBezierPath bezierPathWithRoundedRect:bounds
                                     byRoundingCorners:(UIRectCornerTopLeft | UIRectCornerTopRight)
                                           cornerRadii:CGSizeMake(radius, radius)];
    } else if (indexPath.row == rows - 1) {
        path = [UIBezierPath bezierPathWithRoundedRect:bounds
                                     byRoundingCorners:(UIRectCornerBottomLeft | UIRectCornerBottomRight)
                                           cornerRadii:CGSizeMake(radius, radius)];
    } else {
        path = [UIBezierPath bezierPathWithRect:bounds];
    }

    // Apply mask
    CAShapeLayer *mask = [CAShapeLayer layer];
    mask.path = path.CGPath;
    cell.layer.mask = mask;
    cell.layer.masksToBounds = YES;

    // Optional: shadow in card mode (applied on cell.layer)
    /*if (!useRowCardMode) {
        cell.layer.shadowColor = [UIColor colorWithWhite:0 alpha:0.12].CGColor;
        cell.layer.shadowOpacity = 1.0;
        cell.layer.shadowOffset = CGSizeMake(0, 2);
        cell.layer.shadowRadius = 6;
        cell.layer.masksToBounds = NO; // shadow needs this
    } else {
        cell.layer.shadowOpacity = 0.0;
        cell.layer.masksToBounds = YES;
    }*/
    
    cell.layer.shadowColor = [UIColor colorWithWhite:0 alpha:0.22].CGColor;
    cell.layer.shadowOpacity = 1.0;
    cell.layer.shadowOffset = CGSizeMake(0, 2);
    cell.layer.shadowRadius = 6;
    cell.layer.masksToBounds = NO; // shadow needs this
}



+ (void)addLiquidGlassBorderToView:(UIView *)view cornerRadius:(CGFloat)radius {
    // No-op stub — iOS liquid-glass effect not available in Admin
    view.layer.cornerRadius = radius;
    view.layer.masksToBounds = YES;
}

@end
