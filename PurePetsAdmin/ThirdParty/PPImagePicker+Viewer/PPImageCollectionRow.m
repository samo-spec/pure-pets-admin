//
//  PPImageCollectionRow.m
//  PurePetsAdmin
//
//  XLForm cell wrapping PPImageCollection.
//

#import "PPImageCollectionRow.h"

NSString * const XLFormRowDescriptorTypePPImageCollection = @"XLFormRowDescriptorTypePPImageCollection";

void PPImageCollectionRow_register(void) {
    [[XLFormViewController cellClassesForRowDescriptorTypes]
     setObject:[PPImageCollectionRow class]
        forKey:XLFormRowDescriptorTypePPImageCollection];
}

@interface PPImageCollectionRow ()
@property (nonatomic, strong, readwrite) PPImageCollection *imageCollection;
@property (nonatomic, assign, readwrite) BOOL imagesModified;
@property (nonatomic, assign) BOOL preloadComplete;
@end

@implementation PPImageCollectionRow

#pragma mark - XLForm lifecycle

+ (void)load {
    // Auto-register on class load so callers don't need explicit init.
    PPImageCollectionRow_register();
}

- (void)configure {
    [super configure];
    self.selectionStyle = UITableViewCellSelectionStyleNone;
    _maxImages = 8;

    _imageCollection = [[PPImageCollection alloc] initWithFrame:CGRectZero];
    _imageCollection.translatesAutoresizingMaskIntoConstraints = NO;
    _imageCollection.delegate = self;
    _imageCollection.maxImageCount = _maxImages;
    _imageCollection.allowsEditing = YES;
    _imageCollection.allowsReordering = YES;
    _imageCollection.useArabic = [kLang(@"lang") isEqualToString:@"ar"];

    [self.contentView addSubview:_imageCollection];

    [NSLayoutConstraint activateConstraints:@[
        [_imageCollection.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:16],
        [_imageCollection.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-16],
        [_imageCollection.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:8],
        [_imageCollection.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor constant:-8],
        [_imageCollection.heightAnchor constraintGreaterThanOrEqualToConstant:110]
    ]];
}

- (void)update {
    [super update];

    _imageCollection.maxImageCount = _maxImages;
    _imageCollection.titleText = self.rowDescriptor.title ?: @"";

    // Preload single URL if provided and collection is empty.
    if (_preloadImageURL.length > 0 && [_imageCollection allImages].count == 0 && !_preloadComplete) {
        NSString *urlStr = [_preloadImageURL copy];
        _preloadImageURL = nil; // Only load once
        _preloadComplete = NO;
        _imagesModified = NO;
        __weak typeof(self) weakSelf = self;
        [_imageCollection preloadImagesFromURLs:@[urlStr] completion:^{
            weakSelf.preloadComplete = YES;
        }];
        return;
    }

    // Preload multiple URLs if provided (multi-image editing mode).
    if (_preloadImageURLs.count > 0 && [_imageCollection allImages].count == 0 && !_preloadComplete) {
        NSArray<NSString *> *urls = [_preloadImageURLs copy];
        _preloadImageURLs = nil; // Only load once
        _preloadComplete = NO;
        _imagesModified = NO;
        __weak typeof(self) weakSelf = self;
        [_imageCollection preloadImagesFromURLs:urls completion:^{
            weakSelf.preloadComplete = YES;
        }];
        return;
    }

    // Sync value → collection (if value set externally, e.g. from form values).
    id val = self.rowDescriptor.value;
    if ([val isKindOfClass:[NSArray class]]) {
        NSArray *arr = (NSArray *)val;
        if (arr.count > 0 && [_imageCollection allImages].count == 0) {
            for (id img in arr) {
                if ([img isKindOfClass:[UIImage class]]) {
                    [_imageCollection addImage:img];
                }
            }
        }
    } else if ([val isKindOfClass:[UIImage class]] && [_imageCollection allImages].count == 0) {
        [_imageCollection addImage:(UIImage *)val];
    }
}

- (CGFloat)formDescriptorCellHeightForRowDescriptor:(XLFormRowDescriptor *)rowDescriptor {
    return 126;
}

+ (BOOL)formDescriptorCellCanBecomeFirstResponder {
    return NO;
}

#pragma mark - Setters

- (void)setMaxImages:(NSInteger)maxImages {
    _maxImages = MAX(1, maxImages);
    _imageCollection.maxImageCount = _maxImages;
}

#pragma mark - PPImageCollectionDelegate

- (void)imageCollection:(PPImageCollection *)collection didUpdateImages:(NSArray<UIImage *> *)images {
    // Track whether user actually changed images (vs preload populating them).
    if (_preloadComplete) {
        _imagesModified = YES;
    }

    // Push images into row value.
    if (images.count == 0) {
        self.rowDescriptor.value = nil;
    } else if (_maxImages == 1) {
        // Single-image mode: value is a UIImage (matches old PPPickerRow behavior).
        self.rowDescriptor.value = images.firstObject;
    } else {
        self.rowDescriptor.value = [images copy];
    }
}

- (void)imageCollection:(PPImageCollection *)collection didSelectImage:(UIImage *)image AtIndex:(NSInteger)index {
    // Tap on existing image — viewer is handled internally by PPImageCollection.
}

- (void)imageCollectionDidRequestAddImage:(PPImageCollection *)collection {
    // "Add" button tapped — picker presentation is handled internally by PPImageCollection.
}

@end
