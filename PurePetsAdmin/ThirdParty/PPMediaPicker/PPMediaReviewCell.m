//
//  PPMediaReviewCell.m
//  Pure Pets
//
//  Created by Gemini CLI on 28/03/2026.
//

#import "PPMediaReviewCell.h"

@implementation PPMediaReviewCell

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        [self setupUI];
    }
    return self;
}

- (void)setupUI {
    self.imageView = [[UIImageView alloc] initWithFrame:self.contentView.bounds];
    self.imageView.contentMode = UIViewContentModeScaleAspectFill;
    self.imageView.clipsToBounds = YES;
    self.imageView.layer.cornerRadius = 8;
    self.imageView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [self.contentView addSubview:self.imageView];
    
    self.deleteButton = [UIButton buttonWithType:UIButtonTypeCustom];
    [self.deleteButton setImage:[UIImage systemImageNamed:@"xmark.circle.fill"] forState:UIControlStateNormal];
    self.deleteButton.tintColor = [UIColor systemRedColor];
    [self.deleteButton addTarget:self action:@selector(deleteTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.contentView addSubview:self.deleteButton];
    
    self.editButton = [UIButton buttonWithType:UIButtonTypeCustom];
    [self.editButton setImage:[UIImage systemImageNamed:@"pencil.circle.fill"] forState:UIControlStateNormal];
    self.editButton.tintColor = [UIColor systemBlueColor];
    [self.editButton addTarget:self action:@selector(editTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.contentView addSubview:self.editButton];
    
    self.videoIndicator = [[UIView alloc] initWithFrame:CGRectMake(8, 8, 24, 24)];
    self.videoIndicator.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.5];
    self.videoIndicator.layer.cornerRadius = 12;
    UIImageView *camIcon = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"video.fill"]];
    camIcon.tintColor = [UIColor whiteColor];
    camIcon.frame = CGRectMake(4, 4, 16, 16);
    [self.videoIndicator addSubview:camIcon];
    [self.contentView addSubview:self.videoIndicator];
    
    self.deleteButton.translatesAutoresizingMaskIntoConstraints = NO;
    self.editButton.translatesAutoresizingMaskIntoConstraints = NO;
    self.videoIndicator.translatesAutoresizingMaskIntoConstraints = NO;
    
    [NSLayoutConstraint activateConstraints:@[
        [self.deleteButton.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:4],
        [self.deleteButton.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-4],
        [self.deleteButton.widthAnchor constraintEqualToConstant:24],
        [self.deleteButton.heightAnchor constraintEqualToConstant:24],
        
        [self.editButton.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor constant:-4],
        [self.editButton.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-4],
        [self.editButton.widthAnchor constraintEqualToConstant:24],
        [self.editButton.heightAnchor constraintEqualToConstant:24],
        
        [self.videoIndicator.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:4],
        [self.videoIndicator.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:4],
        [self.videoIndicator.widthAnchor constraintEqualToConstant:24],
        [self.videoIndicator.heightAnchor constraintEqualToConstant:24]
    ]];
}

- (void)configureWithItem:(PPMediaItem *)item {
    if (item.image) {
        self.imageView.image = item.image;
    } else if (item.asset) {
        PHImageRequestOptions *options = [PHImageRequestOptions new];
        options.networkAccessAllowed = YES;
        options.resizeMode = PHImageRequestOptionsResizeModeFast;
        options.deliveryMode = PHImageRequestOptionsDeliveryModeHighQualityFormat;
        
        [[PHImageManager defaultManager] requestImageForAsset:item.asset
                                                   targetSize:self.bounds.size
                                                  contentMode:PHImageContentModeAspectFill
                                                      options:options
                                                resultHandler:^(UIImage * _Nullable result, NSDictionary * _Nullable info) {
            self.imageView.image = result;
        }];
    } else if (item.videoURL) {
        // Generate thumbnail for video
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
            AVURLAsset *asset = [[AVURLAsset alloc] initWithURL:item.videoURL options:nil];
            AVAssetImageGenerator *generator = [[AVAssetImageGenerator alloc] initWithAsset:asset];
            generator.appliesPreferredTrackTransform = YES;
            CMTime time = CMTimeMake(1, 60);
            CGImageRef imageRef = [generator copyCGImageAtTime:time actualTime:NULL error:nil];
            UIImage *thumbnail = [UIImage imageWithCGImage:imageRef];
            CGImageRelease(imageRef);
            dispatch_async(dispatch_get_main_queue(), ^{
                self.imageView.image = thumbnail;
            });
        });
    }
    
    self.videoIndicator.hidden = !item.isVideo;
    [self.editButton setTitle:item.isVideo ? @"Trim" : @"Edit" forState:UIControlStateNormal];
}

- (void)deleteTapped {
    if (self.deleteHandler) self.deleteHandler();
}

- (void)editTapped {
    if (self.editHandler) self.editHandler();
}

@end
