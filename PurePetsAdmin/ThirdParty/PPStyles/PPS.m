//
//  PPS.h
//  PurePetsAdmin
//
//  Created by Mohammed Ahmed on 24/08/2025.
//


//  PPS.m

#import "PPS.h"
#import <QuartzCore/QuartzCore.h>

#pragma mark - Helpers: Padded TextField

@interface PPS_PaddedTextField : UITextField
@property (nonatomic) UIEdgeInsets textInsets;
@end

@implementation PPS_PaddedTextField
- (CGRect)textRectForBounds:(CGRect)bounds { return UIEdgeInsetsInsetRect([super textRectForBounds:bounds], self.textInsets); }
- (CGRect)editingRectForBounds:(CGRect)bounds { return UIEdgeInsetsInsetRect([super editingRectForBounds:bounds], self.textInsets); }
- (CGRect)placeholderRectForBounds:(CGRect)bounds { return UIEdgeInsetsInsetRect([super placeholderRectForBounds:bounds], self.textInsets); }
@end

#pragma mark - String Normalization & Fuzzy

static NSString *PPNormalize(NSString *s, BOOL caseInsensitive, BOOL diacriticsInsensitive) {
    if (!s) return @"";
    NSString *result = [s copy];

    if (diacriticsInsensitive) {
        result = [result stringByFoldingWithOptions:NSDiacriticInsensitiveSearch locale:[NSLocale currentLocale]];
    }
    if (caseInsensitive) {
        result = result.lowercaseString;
    }

    // Simple Arabic unifications (helps typo tolerance)
    // ا/أ/إ/آ -> ا , ى/ي -> ي , ة -> ه
    result = [result stringByReplacingOccurrencesOfString:@"أ" withString:@"ا"];
    result = [result stringByReplacingOccurrencesOfString:@"إ" withString:@"ا"];
    result = [result stringByReplacingOccurrencesOfString:@"آ" withString:@"ا"];
    result = [result stringByReplacingOccurrencesOfString:@"ى" withString:@"ي"];
    result = [result stringByReplacingOccurrencesOfString:@"ة" withString:@"ه"];

    // Arabic digits → Latin digits
    NSDictionary<NSString *, NSString *> *digitMap = @{
        @"٠":@"0",@"١":@"1",@"٢":@"2",@"٣":@"3",@"٤":@"4",
        @"٥":@"5",@"٦":@"6",@"٧":@"7",@"٨":@"8",@"٩":@"9"
    };
    for (NSString *k in digitMap) { result = [result stringByReplacingOccurrencesOfString:k withString:digitMap[k]]; }

    return result;
}

static NSInteger PPLevenshtein(NSString *a, NSString *b) {
    if (!a || !b) return NSIntegerMax/4;
    NSUInteger n = a.length, m = b.length;
    if (n == 0) return (NSInteger)m;
    if (m == 0) return (NSInteger)n;

    // Simple DP with rolling rows
    NSMutableData *prevRowData = [NSMutableData dataWithLength:(m+1)*sizeof(NSInteger)];
    NSMutableData *currRowData = [NSMutableData dataWithLength:(m+1)*sizeof(NSInteger)];
    NSInteger *prev = prevRowData.mutableBytes;
    NSInteger *curr = currRowData.mutableBytes;

    for (NSUInteger j=0;j<=m;j++) prev[j] = (NSInteger)j;

    for (NSUInteger i=1;i<=n;i++) {
        curr[0] = (NSInteger)i;
        unichar ca = [a characterAtIndex:i-1];
        for (NSUInteger j=1;j<=m;j++) {
            unichar cb = [b characterAtIndex:j-1];
            NSInteger cost = (ca == cb) ? 0 : 1;
            NSInteger del = prev[j] + 1;
            NSInteger ins = curr[j-1] + 1;
            NSInteger sub = prev[j-1] + cost;
            NSInteger v = MIN(MIN(del, ins), sub);
            curr[j] = v;
        }
        // swap
        NSInteger *tmp = prev; prev = curr; curr = tmp;
    }
    return prev[m];
}

static CGFloat PPRelevanceScore(NSString *query, NSString *candidate) {
    if (candidate.length == 0) return 0;
    if ([candidate containsString:query]) return 1.0; // direct substring wins
    NSInteger d = PPLevenshtein(query, candidate);
    CGFloat denom = MAX(query.length, candidate.length);
    return MAX(0.f, 1.f - ((CGFloat)d / denom)); // 1..0
}

#pragma mark - PPS

@interface PPS ()
@property (nonatomic, strong) UIVisualEffectView *blurView;
@property (nonatomic, strong) UIView *strokeView;
@property (nonatomic, strong) UIStackView *hStack;
@property (nonatomic, strong) PPS_PaddedTextField *tf;
@property (nonatomic, strong) UIButton *btn1;
@property (nonatomic, strong) UIButton *btn2;

@property (nonatomic, strong) NSTimer *debounceTimer;
@property (nonatomic) NSInteger searchGeneration;
@property (nonatomic, strong) dispatch_queue_t searchQueue;

// Fuzzy store
@property (nonatomic, copy) NSArray *items;
@property (nonatomic, copy) NSArray<NSString *> *normalizedIndex;
@property (nonatomic, copy) PPSearchStringProvider stringProvider;

@property (nonatomic, copy) NSArray<NSArray<NSString *> *> *normalizedFieldsPerItem; // each item -> array of normalized field strings
@property (nonatomic, copy) NSArray<NSString *> *searchKeyPaths;
@property (nonatomic, copy) PPMultiStringProvider multiProvider;

@end

@implementation PPS

#pragma mark Init

- (void)setSearchItems:(NSArray *)items keyPaths:(NSArray<NSString *> *)keyPaths {
    self.items = items ?: @[];
    self.searchKeyPaths = keyPaths ?: @[];
    self.multiProvider = nil;
    self.stringProvider = nil;

    BOOL ci = self.caseInsensitive, di = self.diacriticsInsensitive;
    NSMutableArray *perItem = [NSMutableArray arrayWithCapacity:self.items.count];

    for (id it in self.items) {
        NSMutableArray<NSString *> *fields = [NSMutableArray array];
        for (NSString *kp in self.searchKeyPaths) {
            id v = nil;
            @try { v = [it valueForKeyPath:kp]; } @catch (__unused NSException *e) { v = nil; }
            if ([v isKindOfClass:NSString.class]) {
                [fields addObject:PPNormalize((NSString *)v, ci, di)];
            } else if ([v isKindOfClass:NSArray.class]) {
                // If a field is an array of strings (e.g., tags)
                for (id s in (NSArray *)v) if ([s isKindOfClass:NSString.class]) {
                    [fields addObject:PPNormalize((NSString *)s, ci, di)];
                }
            }
        }
        [perItem addObject:fields.copy];
    }
    self.normalizedFieldsPerItem = perItem.copy;
}

- (void)setSearchItems:(NSArray *)items multiStringProvider:(PPMultiStringProvider)provider {
    self.items = items ?: @[];
    self.multiProvider = provider;
    self.searchKeyPaths = nil;
    self.stringProvider = nil;

    BOOL ci = self.caseInsensitive, di = self.diacriticsInsensitive;
    NSMutableArray *perItem = [NSMutableArray arrayWithCapacity:self.items.count];

    for (id it in self.items) {
        NSArray<NSString *> *raw = provider ? provider(it) : @[];
        NSMutableArray<NSString *> *norm = [NSMutableArray arrayWithCapacity:raw.count];
        for (NSString *s in raw) { [norm addObject:PPNormalize(s ?: @"", ci, di)]; }
        [perItem addObject:norm.copy];
    }
    self.normalizedFieldsPerItem = perItem.copy;
}


- (instancetype)initWithFrame:(CGRect)frame {
    if (self = [super initWithFrame:frame]) { [self commonInit]; }
    return self;
}

- (instancetype)initWithCoder:(NSCoder *)coder {
    if (self = [super initWithCoder:coder]) { [self commonInit]; }
    return self;
}

- (void)commonInit {
    self.backgroundColor = UIColor.clearColor;

    _contentInsets = UIEdgeInsetsMake(8, 12, 8, 8);
    _cornerRadius = 22.0;
    _shadowEnabled = YES;
    _shadowColor = [UIColor colorWithWhite:0 alpha:1.0];
    _shadowOpacity = 0.08;
    _shadowRadius = 8;
    _shadowOffset = CGSizeMake(0, 3);

    _blurEnabled = YES;
    if (@available(iOS 13.0, *)) _blurEffect = [UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemMaterial];
    else _blurEffect = [UIBlurEffect effectWithStyle:UIBlurEffectStyleLight];
    _glassAlpha = 1.0;
    _strokeColor = UIColor.clearColor;

    _debounceInterval = 0.18;
    _returnKeyType = UIReturnKeySearch;

    _fuzzyEnabled = YES;
    _maxEditDistance = 2;
    _minRelevanceScore = 0.55;
    _caseInsensitive = NO;
    _diacriticsInsensitive = YES;
    _maxResults = 50;
    _sortByRelevance = YES;

    _searchQueue = dispatch_queue_create("pp.search.queue", DISPATCH_QUEUE_CONCURRENT);

    // Blur "glass"
    _blurView = [[UIVisualEffectView alloc] initWithEffect:_blurEffect];
    _blurView.translatesAutoresizingMaskIntoConstraints = NO;
    _blurView.alpha = _glassAlpha;
    _blurView.layer.cornerRadius = _cornerRadius;
    _blurView.layer.masksToBounds = YES;

    // Optional 1px stroke for definition on bright backgrounds
    _strokeView = [UIView new];
    _strokeView.translatesAutoresizingMaskIntoConstraints = NO;
    _strokeView.userInteractionEnabled = NO;

    // Text field
    _tf = [PPS_PaddedTextField new];
    _tf.translatesAutoresizingMaskIntoConstraints = NO;
    _tf.textInsets = UIEdgeInsetsMake(0, 8, 0, 8);
    _tf.clearButtonMode = UITextFieldViewModeWhileEditing;
    _tf.returnKeyType = _returnKeyType;
    _tf.delegate = self;
    _tf.font = [Styling fontMedium:16];
    _tf.textAlignment = Language.alignmentForCurrentLanguage;
    _tf.textColor = [UIColor ppTextPrimary];
    _tf.tintColor = AppPrimaryClr;
    _tf.placeholder = kLang(@"SearchHere");

    if (@available(iOS 13.0, *)) {
        /*
         UIImageView *mag = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"magnifyingglass"]];
         mag.contentMode = UIViewContentModeScaleAspectFit;
         mag.tintColor = [UIColor ppTextSecondary];
         mag.frame = CGRectMake(0, 0, 20, 20);
         UIView *lv = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 26, 20)];
         [lv addSubview:mag];
         mag.center = lv.center;
         _tf.leftView = lv;
         _tf.leftViewMode = UITextFieldViewModeAlways;
         */
        
    }

    // Buttons (hidden by default)
    _btn1 = [UIButton buttonWithType:UIButtonTypeSystem];
    _btn1.translatesAutoresizingMaskIntoConstraints = NO;
    _btn1.hidden = YES;
    _btn1.tintColor = AppPrimaryClr;
    _btn2 = [UIButton buttonWithType:UIButtonTypeSystem];
    _btn2.translatesAutoresizingMaskIntoConstraints = NO;
    _btn2.hidden = YES;
    _btn2.tintColor = AppPrimaryClr;
    // Horizontal stack (LTR default) -> [ tf, btn1, btn2 ]
    _hStack = [[UIStackView alloc] initWithArrangedSubviews:@[_tf, _btn1, _btn2]];
    _hStack.translatesAutoresizingMaskIntoConstraints = NO;
    _hStack.axis = UILayoutConstraintAxisHorizontal;
    _hStack.alignment = UIStackViewAlignmentCenter;
    _hStack.distribution = UIStackViewDistributionFill;
    _hStack.spacing = 8;

    // Container hierarchy
    [self addSubview:_blurView];
    [self addSubview:_strokeView];
    [self addSubview:_hStack];

    // Constraints
    [NSLayoutConstraint activateConstraints:@[
        [_blurView.topAnchor constraintEqualToAnchor:self.topAnchor],
        [_blurView.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
        [_blurView.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
        [_blurView.bottomAnchor constraintEqualToAnchor:self.bottomAnchor],

        [_strokeView.topAnchor constraintEqualToAnchor:self.topAnchor],
        [_strokeView.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
        [_strokeView.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
        [_strokeView.bottomAnchor constraintEqualToAnchor:self.bottomAnchor],

        [_hStack.topAnchor constraintEqualToAnchor:self.topAnchor constant:_contentInsets.top],
        [_hStack.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:_contentInsets.left],
        [_hStack.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-_contentInsets.right],
        [_hStack.bottomAnchor constraintEqualToAnchor:self.bottomAnchor constant:-_contentInsets.bottom],

        [_btn1.widthAnchor constraintLessThanOrEqualToConstant:44],
        [_btn1.heightAnchor constraintEqualToConstant:32],
        [_btn2.widthAnchor constraintLessThanOrEqualToConstant:44],
        [_btn2.heightAnchor constraintEqualToConstant:32],
    ]];

    // Corners & shadow (on self)
    self.layer.cornerRadius = _cornerRadius;
    self.layer.masksToBounds = NO;
    [self applyShadow];

    // Stroke 1px
    [self updateStroke];

    // Live text change (debounced)
    
    _tf.font = [Styling fontMedium:16];
    _tf.textAlignment = Language.alignmentForCurrentLanguage;
    
    [_tf addTarget:self action:@selector(_textDidChange:) forControlEvents:UIControlEventEditingChanged];

    // Semantic: default LTR layout as requested
    self.semanticContentAttribute = UISemanticContentAttributeForceLeftToRight;
}

#pragma mark - Public accessors

- (UITextField *)textField { return _tf; }
- (UIButton *)primaryButton { return _btn1; }
- (UIButton *)secondaryButton { return _btn2; }

- (BOOL)focus { return [_tf becomeFirstResponder]; }
- (void)unfocus { [_tf resignFirstResponder]; }

#pragma mark - Config

- (void)setContentInsets:(UIEdgeInsets)contentInsets {
    _contentInsets = contentInsets;
    
    // Re-apply edge constraints
    [NSLayoutConstraint deactivateConstraints:self.constraints];
    [self commonInit]; // easiest safe refresh; for production, update constraints selectively
}

- (void)setCornerRadius:(CGFloat)cornerRadius {
    _cornerRadius = cornerRadius;
    self.layer.cornerRadius = cornerRadius;
    _blurView.layer.cornerRadius = cornerRadius;
}

- (void)setBlurEnabled:(BOOL)blurEnabled {
    _blurEnabled = blurEnabled;
    _blurView.hidden = !blurEnabled;
}

- (void)setBlurEffect:(UIBlurEffect *)blurEffect {
    _blurEffect = blurEffect ?: _blurEffect;
    _blurView.effect = _blurEffect;
}

- (void)setGlassAlpha:(CGFloat)glassAlpha {
    _glassAlpha = glassAlpha;
    _blurView.alpha = glassAlpha;
}

- (void)setReturnKeyType:(UIReturnKeyType)returnKeyType {
    _returnKeyType = returnKeyType;
    _tf.returnKeyType = returnKeyType;
}

- (void)setShadowEnabled:(BOOL)shadowEnabled { _shadowEnabled = shadowEnabled; [self applyShadow]; }
- (void)setShadowColor:(UIColor *)shadowColor { _shadowColor = shadowColor ?: [UIColor colorWithWhite:0 alpha:1]; [self applyShadow]; }
- (void)setShadowOpacity:(CGFloat)shadowOpacity { _shadowOpacity = shadowOpacity; [self applyShadow]; }
- (void)setShadowRadius:(CGFloat)shadowRadius { _shadowRadius = shadowRadius; [self applyShadow]; }
- (void)setShadowOffset:(CGSize)shadowOffset { _shadowOffset = shadowOffset; [self applyShadow]; }

- (void)applyShadow {
    if (_shadowEnabled) {
        self.layer.shadowColor = _shadowColor.CGColor;
        self.layer.shadowOpacity = (float)_shadowOpacity;
        self.layer.shadowRadius = _shadowRadius;
        self.layer.shadowOffset = _shadowOffset;
        self.layer.shadowPath = [UIBezierPath bezierPathWithRoundedRect:self.bounds cornerRadius:self.cornerRadius].CGPath;
    } else {
        self.layer.shadowOpacity = 0.0;
    }
}

- (void)layoutSubviews {
    [super layoutSubviews];
    [self applyShadow];
    [self updateStroke];
}

- (void)updateStroke {
    self.strokeView.layer.cornerRadius = self.cornerRadius;
    self.strokeView.layer.borderWidth = self.strokeColor == UIColor.clearColor ? 0.0 : 1.0 / UIScreen.mainScreen.scale;
    self.strokeView.layer.borderColor = self.strokeColor.CGColor;
}

#pragma mark - Buttons

- (void)configurePrimaryButtonWithImage:(UIImage *)image target:(id)target action:(SEL)action {
    self.showsPrimaryButton = YES;
    if (image) { [_btn1 setImage:image forState:UIControlStateNormal]; }
    [_btn1 removeTarget:nil action:NULL forControlEvents:UIControlEventTouchUpInside];
    if (target && action) { [_btn1 addTarget:target action:action forControlEvents:UIControlEventTouchUpInside]; }
    _btn1.hidden = !self.showsPrimaryButton;
}

- (void)configureSecondaryButtonWithImage:(UIImage *)image target:(id)target action:(SEL)action {
    self.showsSecondaryButton = YES;
    if (image) { [_btn2 setImage:image forState:UIControlStateNormal]; }
    [_btn2 removeTarget:nil action:NULL forControlEvents:UIControlEventTouchUpInside];
    if (target && action) { [_btn2 addTarget:target action:action forControlEvents:UIControlEventTouchUpInside]; }
    _btn2.hidden = !self.showsSecondaryButton;
}

- (void)setShowsPrimaryButton:(BOOL)showsPrimaryButton {
    _showsPrimaryButton = showsPrimaryButton;
    _btn1.hidden = !showsPrimaryButton;
}

- (void)setShowsSecondaryButton:(BOOL)showsSecondaryButton {
    _showsSecondaryButton = showsSecondaryButton;
    _btn2.hidden = !showsSecondaryButton;
}

#pragma mark - UITextFieldDelegate

- (void)_textDidChange:(UITextField *)sender {
    [self.debounceTimer invalidate];
    if (self.debounceInterval <= 0) {
        if ([self.delegate respondsToSelector:@selector(searchView:didChangeText:)]) {
            [self.delegate searchView:self didChangeText:sender.text ?: @""];
        }
        return;
    }
    __weak typeof(self) weakSelf = self;
    self.debounceTimer = [NSTimer scheduledTimerWithTimeInterval:self.debounceInterval repeats:NO block:^(NSTimer * _Nonnull t) {
        __strong typeof(weakSelf) self = weakSelf;
        if ([self.delegate respondsToSelector:@selector(searchView:didChangeText:)]) {
            [self.delegate searchView:self didChangeText:self->_tf.text ?: @""];
        }
    }];
}

- (void)textFieldDidBeginEditing:(UITextField *)textField {
    if ([self.delegate respondsToSelector:@selector(searchViewDidBeginEditing:)]) {
        [self.delegate searchViewDidBeginEditing:self];
    }
}
- (void)textFieldDidEndEditing:(UITextField *)textField {
    if ([self.delegate respondsToSelector:@selector(searchViewDidEndEditing:)]) {
        [self.delegate searchViewDidEndEditing:self];
    }
}
- (BOOL)textFieldShouldReturn:(UITextField *)textField {
    if ([self.delegate respondsToSelector:@selector(searchViewDidSubmit:)]) {
        [self.delegate searchViewDidSubmit:self];
    }
    [textField resignFirstResponder];
    return YES;
}

#pragma mark - Fuzzy Search API

- (void)setSearchItems:(NSArray *)items stringProvider:(PPSearchStringProvider)provider {
    self.items = items ?: @[];
    self.stringProvider = provider;
    if (!provider) { self.normalizedIndex = @[]; return; }

    BOOL ci = self.caseInsensitive, di = self.diacriticsInsensitive;
    NSMutableArray<NSString *> *norm = [NSMutableArray arrayWithCapacity:self.items.count];
    for (id it in self.items) {
        NSString *s = provider(it) ?: @"";
        [norm addObject:PPNormalize(s, ci, di)];
    }
    self.normalizedIndex = norm;
}

- (void)filterAsyncForText:(NSString *)query completion:(PPSearchResultsHandler)completion {
    if (!self.fuzzyEnabled || query.length == 0 || !self.stringProvider) {
        if (completion) completion(query ?: @"", @[]);
        return;
    }

    NSString *normQ = PPNormalize(query, self.caseInsensitive, self.diacriticsInsensitive);
    NSInteger token = ++self.searchGeneration;
    NSArray *items = self.items;
    //NSArray<NSString *> *index = self.normalizedIndex;
    BOOL sortByRel = self.sortByRelevance;
    CGFloat minScore = self.minRelevanceScore;
    NSInteger maxResults = self.maxResults;

    dispatch_async(self.searchQueue, ^{
        NSMutableArray *results = [NSMutableArray array];
        NSMutableArray<NSNumber *> *scores = [NSMutableArray array];

        for (NSInteger i = 0; i < self.items.count; i++) {
            NSArray<NSString *> *fields = (self.normalizedFieldsPerItem.count > 0)
                ? self.normalizedFieldsPerItem[i]
                : (self.normalizedIndex.count > i ? @[ self.normalizedIndex[i] ] : @[]);

            CGFloat best = 0.f;
            for (NSString *cand in fields) {
                CGFloat s = PPRelevanceScore(normQ, cand);
                if (s > best) best = s;
                if (best >= 1.0) break; // exact substring in any field: early win
            }

            if (best >= minScore) {
                [results addObject:items[i]];
                [scores addObject:@(best)];
            }
        }

        if (sortByRel && results.count > 1) {
            NSArray *sorted = [results sortedArrayUsingComparator:^NSComparisonResult(id  _Nonnull obj1, id  _Nonnull obj2) {
                NSUInteger i1 = [results indexOfObjectIdenticalTo:obj1];
                NSUInteger i2 = [results indexOfObjectIdenticalTo:obj2];
                CGFloat s1 = scores[i1].doubleValue;
                CGFloat s2 = scores[i2].doubleValue;
                if (s1 > s2) return NSOrderedAscending;
                if (s1 < s2) return NSOrderedDescending;
                return NSOrderedSame;
            }];
            results = [sorted mutableCopy];
        }

        if (maxResults > 0 && results.count > maxResults) {
            results = [[results subarrayWithRange:NSMakeRange(0, maxResults)] mutableCopy];
        }

        dispatch_async(dispatch_get_main_queue(), ^{
            if (token == self.searchGeneration) { // latest query only
                if (completion) completion(query, results);
            }
        });
    });
}


- (void)tableView:(UITableView *)tableView willDisplayCell:(UITableViewCell *)cell forRowAtIndexPath:(NSIndexPath *)indexPath
{
    [Styling applyBackgroundStyleForTableView:tableView cell:cell indexPath:indexPath useRowCardMode:NO buttonRowIndex:0 buttonSection:1];
}


@end
