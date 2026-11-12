#import "PPProviderSubscriptionPresentation.h"
#import "PPProviderUI.h"
#import "Language.h"
#import "Styling.h"

UILabel *PPSubscriptionLabel(UIFontTextStyle style, CGFloat size, BOOL bold) {
    UILabel *label = [UILabel new];
    label.font = [[UIFontMetrics metricsForTextStyle:style] scaledFontForFont:bold ? [Styling fontBold:size] : [Styling fontRegular:size]];
    label.adjustsFontForContentSizeCategory = YES; label.numberOfLines = 0;
    label.textColor = PPProviderPrimaryTextColor(); label.textAlignment = Language.alignmentForCurrentLanguage;
    return label;
}

static UIStackView *PPSubscriptionColumn(NSArray<UIView *> *views, CGFloat spacing) {
    UIStackView *stack = [[UIStackView alloc] initWithArrangedSubviews:views];
    stack.axis = UILayoutConstraintAxisVertical; stack.spacing = spacing;
    stack.semanticContentAttribute = Language.semanticAttributeForCurrentLanguage;
    return stack;
}

static UIImageView *PPSubscriptionGlyph(NSString *name, UIColor *color) {
    UIImageView *image = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:name withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:18 weight:UIImageSymbolWeightMedium]]];
    image.tintColor = color; image.contentMode = UIViewContentModeScaleAspectFit; image.isAccessibilityElement = NO;
    [image.widthAnchor constraintEqualToConstant:24].active = YES;
    [image.heightAnchor constraintEqualToConstant:24].active = YES;
    return image;
}

// A centered reading column also protects long lines when a sheet is wide.
static void PPSubscriptionPinColumn(UIView *child, UIView *parent, CGFloat top, CGFloat bottom) {
    child.translatesAutoresizingMaskIntoConstraints = NO; [parent addSubview:child];
    NSLayoutConstraint *preferredWidth = [child.widthAnchor constraintEqualToAnchor:parent.widthAnchor constant:-40];
    preferredWidth.priority = UILayoutPriorityDefaultHigh;
    [NSLayoutConstraint activateConstraints:@[[child.topAnchor constraintEqualToAnchor:parent.topAnchor constant:top],
        [child.bottomAnchor constraintEqualToAnchor:parent.bottomAnchor constant:-bottom],
        [child.centerXAnchor constraintEqualToAnchor:parent.centerXAnchor],
        [child.leadingAnchor constraintGreaterThanOrEqualToAnchor:parent.leadingAnchor constant:20],
        [child.trailingAnchor constraintLessThanOrEqualToAnchor:parent.trailingAnchor constant:-20],
        [child.widthAnchor constraintLessThanOrEqualToConstant:640], preferredWidth]];
}

UIView *PPSubscriptionIdentity(NSString *name, NSString *type, NSString *status, UIColor *statusColor) {
    UILabel *nameLabel = PPSubscriptionLabel(UIFontTextStyleTitle1, 28, YES); nameLabel.text = name;
    nameLabel.accessibilityTraits |= UIAccessibilityTraitHeader;
    UILabel *typeLabel = PPSubscriptionLabel(UIFontTextStyleSubheadline, 15, NO); typeLabel.text = type;
    typeLabel.textColor = PPProviderSecondaryTextColor();
    UILabel *stateLabel = PPSubscriptionLabel(UIFontTextStyleSubheadline, 15, YES); stateLabel.text = status;
    stateLabel.textColor = statusColor; stateLabel.hidden = status.length == 0;
    return PPSubscriptionColumn(@[typeLabel, nameLabel, stateLabel], 6);
}

UIView *PPSubscriptionPlanSummary(NSString *caption, NSString *name, NSString *price, NSString *interval) {
    UIView *surface = [UIView new]; surface.backgroundColor = PPProviderSurfaceColor(); surface.layer.cornerRadius = 20;
    UILabel *captionLabel = PPSubscriptionLabel(UIFontTextStyleFootnote, 13, YES); captionLabel.text = caption;
    captionLabel.textColor = PPProviderSecondaryTextColor();
    UILabel *nameLabel = PPSubscriptionLabel(UIFontTextStyleTitle2, 22, YES); nameLabel.text = name;
    UILabel *priceLabel = PPSubscriptionLabel(UIFontTextStyleBody, 17, YES); priceLabel.text = price;
    priceLabel.textColor = PPProviderBrandColor(); priceLabel.hidden = price.length == 0;
    UILabel *intervalLabel = PPSubscriptionLabel(UIFontTextStyleSubheadline, 15, NO); intervalLabel.text = interval;
    intervalLabel.textColor = PPProviderSecondaryTextColor(); intervalLabel.hidden = interval.length == 0;
    UIStackView *stack = PPSubscriptionColumn(@[captionLabel, nameLabel, priceLabel, intervalLabel], 8);
    PPSubscriptionPinColumn(stack, surface, 20, 20);
    return surface;
}

UIView *PPSubscriptionNotice(NSString *message, NSString *symbol, BOOL warning) {
    UILabel *label = PPSubscriptionLabel(UIFontTextStyleFootnote, 13, NO); label.text = message;
    label.textColor = warning ? [UIColor ppError] : PPProviderSecondaryTextColor();
    UIStackView *row = [[UIStackView alloc] initWithArrangedSubviews:@[PPSubscriptionGlyph(symbol, label.textColor), label]];
    row.axis = UILayoutConstraintAxisHorizontal; row.alignment = UIStackViewAlignmentTop; row.spacing = 10;
    row.semanticContentAttribute = Language.semanticAttributeForCurrentLanguage;
    return row;
}

UITableViewCell *PPSubscriptionHostedCell(UIView *content) {
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil];
    cell.backgroundColor = UIColor.clearColor; cell.selectionStyle = UITableViewCellSelectionStyleNone;
    cell.isAccessibilityElement = NO; // Expose hosted headings/notices; fact/action cells explicitly group their content.
    PPSubscriptionPinColumn(content, cell.contentView, 10, 10);
    return cell;
}

UITableViewCell *PPSubscriptionFactCell(NSString *title, NSString *value, NSString *symbol) {
    UILabel *caption = PPSubscriptionLabel(UIFontTextStyleFootnote, 13, NO); caption.text = title;
    caption.textColor = PPProviderSecondaryTextColor();
    UILabel *detail = PPSubscriptionLabel(UIFontTextStyleBody, 17, YES); detail.text = value;
    UIStackView *row = [[UIStackView alloc] initWithArrangedSubviews:@[PPSubscriptionGlyph(symbol, PPProviderSecondaryTextColor()), PPSubscriptionColumn(@[caption, detail], 4)]];
    row.axis = UILayoutConstraintAxisHorizontal; row.alignment = UIStackViewAlignmentTop; row.spacing = 12;
    row.semanticContentAttribute = Language.semanticAttributeForCurrentLanguage;
    UITableViewCell *cell = PPSubscriptionHostedCell(row);
    cell.isAccessibilityElement = YES; cell.accessibilityLabel = title; cell.accessibilityValue = value;
    return cell;
}

UITableViewCell *PPSubscriptionActionCell(NSString *title, NSString *impact, NSString *symbol, BOOL destructive, BOOL emphasized, BOOL enabled) {
    UIColor *accent = destructive ? [UIColor ppError] : PPProviderBrandColor();
    UIView *surface = [UIView new]; surface.layer.cornerRadius = 16;
    surface.backgroundColor = emphasized ? accent : UIColor.clearColor;
    UILabel *titleLabel = PPSubscriptionLabel(UIFontTextStyleHeadline, 17, YES); titleLabel.text = title;
    UILabel *detail = PPSubscriptionLabel(UIFontTextStyleSubheadline, 15, NO); detail.text = impact;
    titleLabel.textColor = emphasized ? UIColor.whiteColor : accent;
    detail.textColor = emphasized ? UIColor.whiteColor : PPProviderSecondaryTextColor();
    UIImageView *chevron = PPSubscriptionGlyph(@"chevron.forward", titleLabel.textColor);
    UIStackView *row = [[UIStackView alloc] initWithArrangedSubviews:@[PPSubscriptionGlyph(symbol, titleLabel.textColor), PPSubscriptionColumn(@[titleLabel, detail], 5), chevron]];
    row.axis = UILayoutConstraintAxisHorizontal; row.alignment = UIStackViewAlignmentCenter; row.spacing = 12;
    row.semanticContentAttribute = Language.semanticAttributeForCurrentLanguage;
    PPSubscriptionPinColumn(row, surface, 16, 16);
    [surface.heightAnchor constraintGreaterThanOrEqualToConstant:60].active = YES;
    UITableViewCell *cell = PPSubscriptionHostedCell(surface);
    cell.selectionStyle = enabled ? UITableViewCellSelectionStyleDefault : UITableViewCellSelectionStyleNone;
    cell.userInteractionEnabled = enabled; cell.contentView.alpha = enabled ? 1 : 0.5;
    cell.isAccessibilityElement = YES; cell.accessibilityLabel = title; cell.accessibilityHint = impact;
    cell.accessibilityTraits = UIAccessibilityTraitButton | (enabled ? 0 : UIAccessibilityTraitNotEnabled);
    return cell;
}

UIView *PPSubscriptionSectionText(NSString *text, BOOL heading) {
    UIView *view = [UIView new];
    UILabel *label = PPSubscriptionLabel(heading ? UIFontTextStyleHeadline : UIFontTextStyleFootnote, heading ? 17 : 13, heading);
    label.text = text; label.textColor = heading ? PPProviderPrimaryTextColor() : PPProviderSecondaryTextColor();
    if (heading) label.accessibilityTraits |= UIAccessibilityTraitHeader;
    PPSubscriptionPinColumn(label, view, heading ? 22 : 4, heading ? 4 : 12);
    return view;
}

UIButton *PPSubscriptionCommitButton(NSString *title, BOOL destructive) {
    UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
    UIButtonConfiguration *configuration = [UIButtonConfiguration filledButtonConfiguration];
    configuration.title = title; configuration.baseBackgroundColor = destructive ? [UIColor ppError] : PPProviderBrandColor();
    configuration.baseForegroundColor = UIColor.whiteColor; configuration.background.cornerRadius = 14;
    configuration.contentInsets = NSDirectionalEdgeInsetsMake(14, 20, 14, 20);
    configuration.titleLineBreakMode = NSLineBreakByWordWrapping;
    configuration.titleTextAttributesTransformer = ^NSDictionary<NSAttributedStringKey,id> *(NSDictionary<NSAttributedStringKey,id> *attributes) {
        NSMutableDictionary *result = attributes.mutableCopy;
        result[NSFontAttributeName] = [[UIFontMetrics metricsForTextStyle:UIFontTextStyleHeadline] scaledFontForFont:[Styling fontBold:17]];
        return result;
    };
    button.configuration = configuration; button.titleLabel.numberOfLines = 0;
    button.titleLabel.adjustsFontForContentSizeCategory = YES;
    [button.heightAnchor constraintGreaterThanOrEqualToConstant:52].active = YES;
    return button;
}

@interface PPSubscriptionReasonView ()
@property (nonatomic, strong, readwrite) UITextView *textView;
@property (nonatomic, strong) UIView *editorSurface;
@property (nonatomic, strong) UILabel *placeholderLabel;
@property (nonatomic, strong) UILabel *countLabel;
@property (nonatomic, assign) BOOL editing;
@end

@implementation PPSubscriptionReasonView
- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        self.editorSurface = [UIView new]; self.editorSurface.layer.cornerRadius = 14;
        self.editorSurface.backgroundColor = PPProviderSurfaceColor(); self.editorSurface.layer.borderWidth = 1;
        self.textView = [UITextView new]; self.textView.translatesAutoresizingMaskIntoConstraints = NO;
        self.textView.font = [[UIFontMetrics metricsForTextStyle:UIFontTextStyleBody] scaledFontForFont:[Styling fontRegular:17]];
        self.textView.adjustsFontForContentSizeCategory = YES; self.textView.textColor = PPProviderPrimaryTextColor();
        self.textView.textAlignment = Language.alignmentForCurrentLanguage; self.textView.backgroundColor = UIColor.clearColor;
        self.textView.textContainerInset = UIEdgeInsetsMake(14, 12, 14, 12); self.textView.textContainer.lineFragmentPadding = 0;
        self.textView.scrollEnabled = NO; self.textView.accessibilityLabel = kLang(@"PartnerSub_Reason");
        self.textView.accessibilityHint = kLang(@"PartnerSub_ReasonHint");
        [self.editorSurface addSubview:self.textView];
        self.placeholderLabel = PPSubscriptionLabel(UIFontTextStyleBody, 17, NO);
        self.placeholderLabel.text = kLang(@"PartnerSub_ReasonPlaceholder"); self.placeholderLabel.textColor = PPProviderSecondaryTextColor();
        self.placeholderLabel.translatesAutoresizingMaskIntoConstraints = NO; self.placeholderLabel.userInteractionEnabled = NO;
        self.placeholderLabel.isAccessibilityElement = NO; [self.editorSurface addSubview:self.placeholderLabel];
        [NSLayoutConstraint activateConstraints:@[[self.textView.leadingAnchor constraintEqualToAnchor:self.editorSurface.leadingAnchor],
            [self.textView.trailingAnchor constraintEqualToAnchor:self.editorSurface.trailingAnchor],
            [self.textView.topAnchor constraintEqualToAnchor:self.editorSurface.topAnchor],
            [self.textView.bottomAnchor constraintEqualToAnchor:self.editorSurface.bottomAnchor],
            [self.textView.heightAnchor constraintGreaterThanOrEqualToConstant:132],
            [self.placeholderLabel.leadingAnchor constraintEqualToAnchor:self.editorSurface.leadingAnchor constant:12],
            [self.placeholderLabel.trailingAnchor constraintEqualToAnchor:self.editorSurface.trailingAnchor constant:-12],
            [self.placeholderLabel.topAnchor constraintEqualToAnchor:self.editorSurface.topAnchor constant:14],
            [self.placeholderLabel.bottomAnchor constraintLessThanOrEqualToAnchor:self.editorSurface.bottomAnchor constant:-14]]];
        self.countLabel = PPSubscriptionLabel(UIFontTextStyleCaption1, 12, NO);
        self.countLabel.textAlignment = Language.alignmentForCurrentLanguage; self.countLabel.textColor = PPProviderSecondaryTextColor();
        self.countLabel.accessibilityLabel = kLang(@"PartnerSub_ReasonCountLabel");
        UIStackView *stack = PPSubscriptionColumn(@[self.editorSurface, self.countLabel], 8);
        stack.translatesAutoresizingMaskIntoConstraints = NO; [self addSubview:stack];
        [NSLayoutConstraint activateConstraints:@[[stack.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
            [stack.trailingAnchor constraintEqualToAnchor:self.trailingAnchor], [stack.topAnchor constraintEqualToAnchor:self.topAnchor],
            [stack.bottomAnchor constraintEqualToAnchor:self.bottomAnchor]]];
        [self updateBorder];
    }
    return self;
}
- (void)updateCount:(NSUInteger)count limit:(NSUInteger)limit placeholderVisible:(BOOL)placeholderVisible exceedsLimit:(BOOL)exceedsLimit {
    self.placeholderLabel.hidden = !placeholderVisible;
    self.countLabel.text = [NSString stringWithFormat:kLang(@"PartnerSub_ReasonCount"), (unsigned long)count, (unsigned long)limit];
    self.countLabel.accessibilityValue = self.countLabel.text;
    self.countLabel.textColor = exceedsLimit ? [UIColor ppError] : PPProviderSecondaryTextColor();
}
- (void)setEditing:(BOOL)editing { _editing = editing; [self updateBorder]; }
- (void)updateBorder {
    self.editorSurface.layer.borderWidth = self.editing ? 1.5 : 1;
    self.editorSurface.layer.borderColor = (self.editing ? PPProviderBrandColor() : [UIColor ppSurfaceBorder]).CGColor;
}
- (void)traitCollectionDidChange:(UITraitCollection *)previousTraitCollection {
    [super traitCollectionDidChange:previousTraitCollection]; [self updateBorder];
}
@end
