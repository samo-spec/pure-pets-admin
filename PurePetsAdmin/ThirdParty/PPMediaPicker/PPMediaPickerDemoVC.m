//
//  PPMediaPickerDemoVC.m
//  Pure Pets
//
//  Created by Gemini CLI on 28/03/2026.
//

#import "PPMediaPickerDemoVC.h"
#import "PPMediaPicker.h"

@interface PPMediaPickerDemoVC () <PPMediaPickerDelegate>

@property (nonatomic, strong) PPMediaPicker *mediaPicker;
@property (nonatomic, strong) UITextView *logView;

@end

@implementation PPMediaPickerDemoVC

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor ppBackground];
    self.title = @"Media Picker Demo";
    
    UIButton *btn = [UIButton buttonWithType:UIButtonTypeSystem];
    [btn setTitle:@"Open Media Picker" forState:UIControlStateNormal];
    [btn addTarget:self action:@selector(openPicker) forControlEvents:UIControlEventTouchUpInside];
    btn.frame = CGRectMake(0, 0, 200, 50);
    btn.center = CGPointMake(self.view.center.x, 150);
    [self.view addSubview:btn];
    
    self.logView = [[UITextView alloc] initWithFrame:CGRectMake(20, 200, self.view.bounds.size.width - 40, 400)];
    self.logView.editable = NO;
    self.logView.layer.borderWidth = 1;
    self.logView.layer.borderColor = [UIColor lightGrayColor].CGColor;
    [self.view addSubview:self.logView];
    
    self.mediaPicker = [[PPMediaPicker alloc] initWithPresentingViewController:self];
    self.mediaPicker.delegate = self;
}

- (void)openPicker {
    [self.mediaPicker openLibrary];
}

#pragma mark - PPMediaPickerDelegate

- (void)mediaPicker:(PPMediaPicker *)picker didFinishWithMedia:(NSArray<PPMediaItem *> *)media {
    NSMutableString *log = [NSMutableString stringWithString:@"Selected Media:\n"];
    for (PPMediaItem *item in media) {
        NSString *type = item.isVideo ? @"Video" : @"Image";
        NSString *edited = item.isEdited ? @"(Edited)" : @"";
        [log appendFormat:@"- %@ %@: %@\n", type, edited, item.uniqueID];
    }
    self.logView.text = log;
}

- (void)mediaPickerDidCancel:(PPMediaPicker *)picker {
    self.logView.text = @"Picker Cancelled";
}

@end
