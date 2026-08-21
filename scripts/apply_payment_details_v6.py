#!/usr/bin/env python3
from pathlib import Path
import re

path = Path('PurePetsAdmin/Payments/PPPaymentDetailsViewController.m')
s = path.read_text(encoding='utf-8')

start = s.index('@implementation PPPaymentNextStepCell')
end_marker = '@end\n\n@class PPPaymentRequestDetailsViewController;'
end = s.index(end_marker, start)

replacement = r'''@implementation PPPaymentNextStepCell {
    UIView *_surfaceView;
    UIView *_statusContainer;
    UIImageView *_workflowIconView;
    UILabel *_captionLabel;
    UILabel *_statusLabel;
    UILabel *_subtitleLabel;
    UIButton *_actionButton;
    UIStackView *_actionRow;
}

static UIFont *PPPaymentDetailsScaledFont(UIFont *baseFont, UIFontTextStyle textStyle)
{
    if (!baseFont) return [UIFont preferredFontForTextStyle:textStyle];
    return [[UIFontMetrics metricsForTextStyle:textStyle] scaledFontForFont:baseFont];
}

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier
{
    self = [super initWithStyle:style reuseIdentifier:reuseIdentifier];
    if (!self) return nil;

    self.backgroundColor = UIColor.clearColor;
    self.contentView.backgroundColor = UIColor.clearColor;
    self.selectionStyle = UITableViewCellSelectionStyleNone;

    _surfaceView = [UIView new];
    _surfaceView.translatesAutoresizingMaskIntoConstraints = NO;
    _surfaceView.backgroundColor = [UIColor ppElevatedSurface];
    PPApplyContinuousCorners(_surfaceView, PPCornerCard);
    _surfaceView.layer.borderWidth = 1.0 / UIScreen.mainScreen.scale;
    _surfaceView.layer.borderColor = [UIColor ppSurfaceBorder].CGColor;
    [self.contentView addSubview:_surfaceView];

    _captionLabel = [UILabel new];
    _captionLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _captionLabel.font = PPPaymentDetailsScaledFont([Styling fontMedium:12], UIFontTextStyleCaption1);
    _captionLabel.adjustsFontForContentSizeCategory = YES;
    _captionLabel.textColor = [UIColor ppTextSecondary];
    _captionLabel.text = kLang(@"PaymentMgmt_Field_Workflow");
    _captionLabel.numberOfLines = 0;

    _statusContainer = [UIView new];
    _statusContainer.translatesAutoresizingMaskIntoConstraints = NO;
    PPApplyContinuousCorners(_statusContainer, PPCornerSmall);

    _workflowIconView = [UIImageView new];
    _workflowIconView.translatesAutoresizingMaskIntoConstraints = NO;
    _workflowIconView.contentMode = UIViewContentModeScaleAspectFit;
    [_statusContainer addSubview:_workflowIconView];

    _statusLabel = [UILabel new];
    _statusLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _statusLabel.font = PPPaymentDetailsScaledFont([Styling fontBold:13], UIFontTextStyleCallout);
    _statusLabel.adjustsFontForContentSizeCategory = YES;
    _statusLabel.numberOfLines = 0;
    [_statusContainer addSubview:_statusLabel];

    _actionButton = [UIButton buttonWithType:UIButtonTypeSystem];
    _actionButton.translatesAutoresizingMaskIntoConstraints = NO;
    PPApplyContinuousCorners(_actionButton, PPCorner16);
    _actionButton.titleLabel.font = PPPaymentDetailsScaledFont([Styling fontBold:14], UIFontTextStyleCallout);
    _actionButton.titleLabel.adjustsFontForContentSizeCategory = YES;
    _actionButton.titleLabel.numberOfLines = 0;
    _actionButton.titleLabel.textAlignment = NSTextAlignmentCenter;
    _actionButton.contentEdgeInsets = UIEdgeInsetsMake(PPSpaceMD, PPSpaceBase, PPSpaceMD, PPSpaceBase);
    [_actionButton setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    [_actionButton.heightAnchor constraintGreaterThanOrEqualToConstant:PPTouchTargetMin].active = YES;

    _subtitleLabel = [UILabel new];
    _subtitleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _subtitleLabel.font = PPPaymentDetailsScaledFont([Styling fontRegular:13], UIFontTextStyleFootnote);
    _subtitleLabel.adjustsFontForContentSizeCategory = YES;
    _subtitleLabel.textColor = [UIColor ppTextSecondary];
    _subtitleLabel.numberOfLines = 0;

    _actionRow = [[UIStackView alloc] initWithArrangedSubviews:@[_statusContainer, _actionButton]];
    _actionRow.translatesAutoresizingMaskIntoConstraints = NO;
    _actionRow.axis = UILayoutConstraintAxisHorizontal;
    _actionRow.alignment = UIStackViewAlignmentCenter;
    _actionRow.spacing = PPSpaceMD;

    UIStackView *contentStack = [[UIStackView alloc] initWithArrangedSubviews:@[_captionLabel, _actionRow, _subtitleLabel]];
    contentStack.translatesAutoresizingMaskIntoConstraints = NO;
    contentStack.axis = UILayoutConstraintAxisVertical;
    contentStack.spacing = PPSpaceMD;
    [_surfaceView addSubview:contentStack];

    [NSLayoutConstraint activateConstraints:@[
        [_surfaceView.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:PPSpaceSM],
        [_surfaceView.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor],
        [_surfaceView.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor],
        [_surfaceView.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor constant:-PPSpaceSM],

        [contentStack.topAnchor constraintEqualToAnchor:_surfaceView.topAnchor constant:PPSpaceBase],
        [contentStack.leadingAnchor constraintEqualToAnchor:_surfaceView.leadingAnchor constant:PPSpaceBase],
        [contentStack.trailingAnchor constraintEqualToAnchor:_surfaceView.trailingAnchor constant:-PPSpaceBase],
        [contentStack.bottomAnchor constraintEqualToAnchor:_surfaceView.bottomAnchor constant:-PPSpaceBase],

        [_workflowIconView.leadingAnchor constraintEqualToAnchor:_statusContainer.leadingAnchor constant:PPSpaceSM],
        [_workflowIconView.centerYAnchor constraintEqualToAnchor:_statusContainer.centerYAnchor],
        [_workflowIconView.widthAnchor constraintEqualToConstant:17.0],
        [_workflowIconView.heightAnchor constraintEqualToConstant:17.0],
        [_statusLabel.leadingAnchor constraintEqualToAnchor:_workflowIconView.trailingAnchor constant:PPSpaceSM],
        [_statusLabel.trailingAnchor constraintEqualToAnchor:_statusContainer.trailingAnchor constant:-PPSpaceSM],
        [_statusLabel.topAnchor constraintEqualToAnchor:_statusContainer.topAnchor constant:PPSpaceSM],
        [_statusLabel.bottomAnchor constraintEqualToAnchor:_statusContainer.bottomAnchor constant:-PPSpaceSM],
    ]];

    [self pp_refreshAdaptiveLayout];
    return self;
}

- (UIButton *)actionButton
{
    return _actionButton;
}

- (void)traitCollectionDidChange:(UITraitCollection *)previousTraitCollection
{
    [super traitCollectionDidChange:previousTraitCollection];
    [self pp_refreshAdaptiveLayout];
}

- (void)pp_refreshAdaptiveLayout
{
    BOOL accessibilitySize = UIContentSizeCategoryIsAccessibilityCategory(self.traitCollection.preferredContentSizeCategory);
    _actionRow.axis = accessibilitySize ? UILayoutConstraintAxisVertical : UILayoutConstraintAxisHorizontal;
    _actionRow.alignment = accessibilitySize ? UIStackViewAlignmentFill : UIStackViewAlignmentCenter;
}

- (void)prepareForReuse
{
    [super prepareForReuse];
    [_actionButton removeTarget:nil action:NULL forControlEvents:UIControlEventTouchUpInside];
}

- (void)configureWithStatusTitle:(NSString *)statusTitle
                     statusColor:(UIColor *)statusColor
                     actionTitle:(NSString *)actionTitle
                      actionTint:(UIColor *)actionTint
                        subtitle:(NSString *)subtitle
{
    UISemanticContentAttribute semantic = [Language semanticAttributeForCurrentLanguage];
    NSTextAlignment alignment = [Language alignmentForCurrentLanguage];
    self.semanticContentAttribute = semantic;
    self.contentView.semanticContentAttribute = semantic;
    _surfaceView.semanticContentAttribute = semantic;
    _captionLabel.textAlignment = alignment;
    _statusLabel.textAlignment = alignment;
    _subtitleLabel.textAlignment = alignment;

    UIColor *resolvedStatusColor = statusColor ?: [UIColor ppPrimary];
    UIColor *resolvedActionTint = actionTint ?: [UIColor ppPrimary];
    _statusContainer.backgroundColor = [resolvedStatusColor colorWithAlphaComponent:0.10];
    _statusContainer.layer.borderWidth = 1.0 / UIScreen.mainScreen.scale;
    _statusContainer.layer.borderColor = [resolvedStatusColor colorWithAlphaComponent:0.20].CGColor;
    _workflowIconView.tintColor = resolvedStatusColor;
    _workflowIconView.image = [[UIImage systemImageNamed:@"arrowshape.turn.up.right.fill"] imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
    _statusLabel.text = statusTitle ?: @"--";
    _statusLabel.textColor = resolvedStatusColor;

    [_actionButton setTitle:actionTitle ?: @"--" forState:UIControlStateNormal];
    _actionButton.backgroundColor = resolvedActionTint;
    _actionButton.accessibilityLabel = actionTitle ?: @"";
    _subtitleLabel.text = subtitle;
    _subtitleLabel.hidden = PPPaymentAdminDetailsTrimmedString(subtitle).length == 0;

    _statusContainer.isAccessibilityElement = YES;
    _statusContainer.accessibilityLabel = statusTitle ?: @"";
    _workflowIconView.accessibilityElementsHidden = YES;
    _statusLabel.isAccessibilityElement = NO;
    [self pp_refreshAdaptiveLayout];
}

@end

@class PPPaymentRequestDetailsViewController;'''

s = s[:start] + replacement + s[end + len(end_marker):]
s = s.replace('self.refreshControl.tintColor = [UIColor ppPrimaryShiner];', 'self.refreshControl.tintColor = [UIColor ppPrimary];')
s = s.replace('subtitle:error.localizedDescription ?: kLang(@"PaymentMgmt_Error_LoadPaymentDetails")', 'subtitle:kLang(@"PaymentMgmt_Error_LoadPaymentDetails")')
s = s.replace(
    'cell.textLabel.font = [Styling fontBold:15];\n        cell.detailTextLabel.font = [Styling fontRegular:13];',
    'cell.textLabel.font = PPPaymentDetailsScaledFont([Styling fontBold:15], UIFontTextStyleHeadline);\n        cell.textLabel.adjustsFontForContentSizeCategory = YES;\n        cell.detailTextLabel.font = PPPaymentDetailsScaledFont([Styling fontRegular:13], UIFontTextStyleSubheadline);\n        cell.detailTextLabel.adjustsFontForContentSizeCategory = YES;'
)
path.write_text(s, encoding='utf-8')
print('Applied Payment Details V6 refinements')
