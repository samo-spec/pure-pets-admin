# PPFormEngine — UIKit Form Engine + Pixel-Perfect Rows

This package contains a reusable Objective-C UIKit form engine and field row UI.

Files:

- `PPFormEngine.h`
- `PPFormEngine.m`

## What it provides

- Text input row
- Phone row
- Number row
- Picker row
- Attachment row
- TextView row
- Form engine container
- Values dictionary
- Validation
- Error display
- Enable/disable
- Show/hide fields
- Picker tap callbacks
- Attachment tap callbacks
- Remove attachment callback
- Text change callback

## Integration

Drag both files into Xcode and tick your app target.

```objc
#import "PPFormEngine.h"
```

## Example

```objc
PPFormStyle *style = [PPFormStyle defaultStyle];

// Match your project theme exactly:
style.cardBackgroundColor = PPProviderSheetSurfaceColor();
style.fieldBackgroundColor = [PPProviderSheetSoftFillColor() colorWithAlphaComponent:0.42];
style.accentColor = PPProviderSheetAccentColor();
style.primaryTextColor = PPProviderSheetPrimaryTextColor();
style.secondaryTextColor = PPProviderSheetSecondaryTextColor();
style.shadowColor = PPProviderSheetShadowColor();
style.titleFont = [Styling fontBold:11.5];
style.inputFont = [Styling fontMedium:15.0];
style.placeholderFont = [Styling fontMedium:14.0];
style.errorFont = [Styling fontMedium:11.0];

self.formView = [[PPFormEngineView alloc] initWithStyle:style];

PPFormFieldConfig *fullName =
[PPFormFieldConfig fieldWithIdentifier:@"fullName"
                                 title:kLang(@"ProviderFullNameField")
                           placeholder:kLang(@"ProviderFullNamePlaceholder")
                             inputType:PPFormInputTypeText];
fullName.required = YES;

PPFormFieldConfig *phone =
[PPFormFieldConfig fieldWithIdentifier:@"phone"
                                 title:kLang(@"ProviderPhoneField")
                           placeholder:kLang(@"ProviderPhonePlaceholder")
                             inputType:PPFormInputTypePhone];
phone.required = YES;

PPFormFieldConfig *city =
[PPFormFieldConfig fieldWithIdentifier:@"city"
                                 title:kLang(@"ProviderCityField")
                           placeholder:kLang(@"ProviderCityPlaceholder")
                             inputType:PPFormInputTypePicker];
__weak typeof(self) weakSelf = self;
city.pickerTapBlock = ^(PPFormFieldConfig *config, PPFormFieldRowView *row) {
    [weakSelf pp_showCityPicker];
};

PPFormFieldConfig *cr =
[PPFormFieldConfig fieldWithIdentifier:@"commercialRegistration"
                                 title:kLang(@"ProviderCommercialRegistrationField")
                           placeholder:kLang(@"ProviderCommercialRegistrationPlaceholder")
                             inputType:PPFormInputTypeAttachment];
cr.attachmentTitle = kLang(@"ProviderAttachmentAddTitle");
cr.attachmentSubtitle = kLang(@"ProviderAttachmentAddSubtitle");
cr.attachmentTapBlock = ^(PPFormFieldConfig *config, PPFormFieldRowView *row) {
    [weakSelf pp_attachButtonTappedForIdentifier:config.identifier];
};

PPFormFieldConfig *notes =
[PPFormFieldConfig fieldWithIdentifier:@"notes"
                                 title:kLang(@"ProviderNotesField")
                           placeholder:@""
                             inputType:PPFormInputTypeTextView];

[self.formView setFields:@[fullName, phone, city, cr, notes]];
```

## Reading data

```objc
NSDictionary *values = [self.formView values];
NSString *fullName = values[@"fullName"];
```

## Validation

```objc
if (![self.formView validate]) {
    NSDictionary *errors = [self.formView validationErrors];
    return;
}
```

## Set a custom validation

```objc
phone.validationBlock = ^NSString *(NSString *value, PPFormFieldConfig *config) {
    if (value.length < 8) {
        return @"Invalid phone number";
    }
    return nil;
};
```

## Update picker value

```objc
[self.formView setValue:@"Doha" forIdentifier:@"city"];
```

## Update attachment state

```objc
[self.formView setAttachmentForIdentifier:@"commercialRegistration"
                                    title:kLang(@"ProviderDocumentAttached")
                                 subtitle:kLang(@"ProviderAttachDocumentHint")
                                    image:[UIImage systemImageNamed:@"doc.text.fill"]
                                  loading:NO
                       removeButtonHidden:NO];
```

## Notes

This is a form engine, but it intentionally does not know anything about:

- API calls
- Firebase
- app routes
- onboarding models
- business rules
- city source/data source

Those stay inside your controller/service layer.
