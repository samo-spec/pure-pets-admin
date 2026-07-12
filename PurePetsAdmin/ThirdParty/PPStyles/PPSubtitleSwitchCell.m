//
//  XLFormSubtitleSwitchCell.m
//  PurePetsAdmin
//
//  Created by Mohammed Ahmed on 28/08/2025.
//


// In XLFormSubtitleSwitchCell.m
#import "PPSubtitleSwitchCell.h"

@implementation XLFormSubtitleSwitchCelll

+ (void)load {
    // Register globally
    [[XLFormViewController cellClassesForRowDescriptorTypes] setObject:self
                                                                forKey:@"XLFormSubtitleSwitchCell"];
}

- (id)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
    self = [super initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:reuseIdentifier];
    if (self) {
        self.titleLabel = self.textLabel;
        self.subtitleLabel = self.detailTextLabel;

        self.titleLabel.font = [Styling fontMedium:16];
        self.subtitleLabel.font = [Styling fontMedium:13];
        self.subtitleLabel.textColor = SeconderyTextClr;


        [self.switchControl addTarget:self
                               action:@selector(switchChanged:)
                     forControlEvents:UIControlEventValueChanged];
        self.accessoryView = self.switchControl;
    }
    return self;
}

- (void)configure {
    [super configure];
    self.selectionStyle = UITableViewCellSelectionStyleNone;
}

- (void)update {
    [super update];

    self.titleLabel.text = self.rowDescriptor.title;
    self.subtitleLabel.text = self.rowDescriptor.cellConfig[@"subtitle"] ?: @"";

    self.switchControl.on = [self.rowDescriptor.value boolValue];
}

- (void)switchChanged:(UISwitch *)sender {
    id oldVal = self.rowDescriptor.value;
    id newVal = @(sender.isOn);

    self.rowDescriptor.value = newVal;

    if (self.rowDescriptor.onChangeBlock) {
        self.rowDescriptor.onChangeBlock(oldVal, newVal, self.rowDescriptor);
    }
}

@end
