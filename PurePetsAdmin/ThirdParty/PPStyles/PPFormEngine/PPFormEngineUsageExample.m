//
//  PPFormEngineUsageExample.m
//
//  Example only. Do not add this file to target unless you want to test quickly.
//

#import "PPFormEngine.h"

@interface PPExampleFormController : UIViewController
@property (nonatomic, strong) PPFormEngineView *formView;
@end

@implementation PPExampleFormController

- (void)viewDidLoad {
    [super viewDidLoad];

    PPFormStyle *style = [PPFormStyle defaultStyle];

    self.formView = [[PPFormEngineView alloc] initWithStyle:style];
    [self.view addSubview:self.formView];

    [NSLayoutConstraint activateConstraints:@[
        [self.formView.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor constant:20.0],
        [self.formView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:20.0],
        [self.formView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-20.0],
    ]];

    __weak typeof(self) weakSelf = self;

    PPFormFieldConfig *fullName = [PPFormFieldConfig fieldWithIdentifier:@"fullName"
                                                                   title:@"Full name"
                                                             placeholder:@"Enter full name"
                                                               inputType:PPFormInputTypeText];
    fullName.required = YES;

    PPFormFieldConfig *phone = [PPFormFieldConfig fieldWithIdentifier:@"phone"
                                                                title:@"Mobile number"
                                                          placeholder:@"Enter mobile number"
                                                            inputType:PPFormInputTypePhone];
    phone.required = YES;

    PPFormFieldConfig *cr = [PPFormFieldConfig fieldWithIdentifier:@"cr"
                                                            title:@"Commercial registration"
                                                      placeholder:@"CR number"
                                                        inputType:PPFormInputTypeAttachment];
    cr.required = YES;
    cr.attachmentTitle = @"Attach document";
    cr.attachmentSubtitle = @"Camera, photos, scan, or files";
    cr.attachmentTapBlock = ^(PPFormFieldConfig *config, PPFormFieldRowView *row) {
        NSLog(@"Attachment tapped: %@", config.identifier);
        [weakSelf.formView setAttachmentForIdentifier:config.identifier
                                                title:@"Document attached"
                                             subtitle:@"Ready to upload"
                                                image:[UIImage systemImageNamed:@"doc.text.fill"]
                                              loading:NO
                                   removeButtonHidden:NO];
    };

    PPFormFieldConfig *city = [PPFormFieldConfig fieldWithIdentifier:@"city"
                                                               title:@"City"
                                                         placeholder:@"Select city"
                                                           inputType:PPFormInputTypePicker];
    city.pickerTapBlock = ^(PPFormFieldConfig *config, PPFormFieldRowView *row) {
        [weakSelf.formView setValue:@"Doha" forIdentifier:config.identifier];
    };

    PPFormFieldConfig *notes = [PPFormFieldConfig fieldWithIdentifier:@"notes"
                                                                title:@"Notes"
                                                          placeholder:@""
                                                            inputType:PPFormInputTypeTextView];

    [self.formView setFields:@[fullName, phone, cr, city, notes]];
}

@end
