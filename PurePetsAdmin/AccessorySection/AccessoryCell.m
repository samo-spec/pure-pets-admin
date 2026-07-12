//
//  AccessoryCell 2.h
//  PurePetsAdmin
//
//  Created by Mohammed Ahmed on 22/08/2025.
//


//
//  AccessoryCell.m
//  PurePetsAdmin
//
//  Created by Admin on 22/08/2025.
//

#import "AccessoryCell.h"
#import "PetAccessory.h"
#import "UIImageView+WebCache.h"

@interface AccessoryCell ()
@property (nonatomic, strong) UIView *cardView;
@property (nonatomic, strong) UIImageView *thumbView;
@property (nonatomic, strong) UILabel *nameLabel;
@property (nonatomic, strong) UILabel *priceLabel;
@property (nonatomic, strong) UILabel *quantityLabel;
@end

@implementation AccessoryCell

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
    if (self = [super initWithStyle:style reuseIdentifier:reuseIdentifier]) {
        self.backgroundColor = UIColor.clearColor;
        self.selectionStyle = UITableViewCellSelectionStyleNone;
        
        float rd = 12;
        // Card container
        _cardView = [[UIView alloc] init];
        _cardView.translatesAutoresizingMaskIntoConstraints = NO;
        _cardView.backgroundColor = UIColor.systemBackgroundColor;
        //_cardView.layer.cornerRadius = rd;
        _cardView.layer.shadowColor = [UIColor blackColor].CGColor;
        _cardView.layer.shadowOpacity = 0.0;
        _cardView.layer.shadowRadius = 0;
        _cardView.layer.shadowOffset = CGSizeMake(0, 2);
        [self.contentView addSubview:_cardView];
        
        // Thumbnail
        _thumbView = [[UIImageView alloc] init];
        _thumbView.translatesAutoresizingMaskIntoConstraints = NO;
        _thumbView.contentMode = UIViewContentModeScaleAspectFill;
        _thumbView.clipsToBounds = YES;
        _thumbView.layer.cornerRadius = rd;
        [_cardView addSubview:_thumbView];
        
        // Name
        _nameLabel = [[UILabel alloc] init];
        _nameLabel.translatesAutoresizingMaskIntoConstraints = NO;
        _nameLabel.font = [Styling fontBold:15];
        _nameLabel.textAlignment = Language.alignmentForCurrentLanguage;
        [_cardView addSubview:_nameLabel];
        
        // Price
        _priceLabel = [[UILabel alloc] init];
        _priceLabel.translatesAutoresizingMaskIntoConstraints = NO;
        _priceLabel.font = [Styling fontMedium:15];
        _priceLabel.textColor = SeconderyTextClr;
        _priceLabel.textAlignment = Language.alignmentForCurrentLanguage;
        [_cardView addSubview:_priceLabel];
        
        // Quantity
        _quantityLabel = [[UILabel alloc] init];
        _quantityLabel.translatesAutoresizingMaskIntoConstraints = NO;
        _quantityLabel.font =[Styling fontMedium:15];
        _quantityLabel.textColor = AppPrimaryClr;
        _quantityLabel.textAlignment = Language.alignmentForCurrentLanguage;
        [_cardView addSubview:_quantityLabel];
        
        // Constraints
        [NSLayoutConstraint activateConstraints:@[
            [_cardView.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:0],
            [_cardView.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:0],
            [_cardView.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:0],
            [_cardView.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor constant:0],
            
            [_thumbView.leadingAnchor constraintEqualToAnchor:_cardView.leadingAnchor constant:8],
            [_thumbView.centerYAnchor constraintEqualToAnchor:_cardView.centerYAnchor],
            [_thumbView.widthAnchor constraintEqualToConstant:70],
            [_thumbView.heightAnchor constraintEqualToConstant:70],
            
            [_nameLabel.topAnchor constraintEqualToAnchor:_cardView.topAnchor constant:12],
            [_nameLabel.leadingAnchor constraintEqualToAnchor:_thumbView.trailingAnchor constant:12],
            [_nameLabel.trailingAnchor constraintEqualToAnchor:_cardView.trailingAnchor constant:-12],
            
            [_priceLabel.topAnchor constraintEqualToAnchor:_nameLabel.bottomAnchor constant:4],
            [_priceLabel.leadingAnchor constraintEqualToAnchor:_thumbView.trailingAnchor constant:12],
            
            [_quantityLabel.topAnchor constraintEqualToAnchor:_priceLabel.bottomAnchor constant:4],
            [_quantityLabel.leadingAnchor constraintEqualToAnchor:_thumbView.trailingAnchor constant:12],
            [_quantityLabel.bottomAnchor constraintLessThanOrEqualToAnchor:_cardView.bottomAnchor constant:-12]
        ]];
    }
    return self;
}

- (void)prepareForReuse {
    [super prepareForReuse];
    self.thumbView.image = nil;
}

- (void)configureWithAccessory:(PetAccessory *)accessory {
    _nameLabel.text = accessory.name ?: @"-";
    _priceLabel.text = [NSString stringWithFormat:@"%@ %@", accessory.price ?: @(0), kLang(@"QAR")];
    
    NSInteger qty = MAX(0, accessory.quantity);
    _quantityLabel.text = [NSString stringWithFormat:@"%@: %ld", kLang(@"Qty"), (long)qty];
    _quantityLabel.textColor = qty == 0 ? UIColor.systemRedColor : UIColor.secondaryLabelColor;
    
    if (accessory.imageURLsArray.count > 0) {
        NSString *url = accessory.imageURLsArray.firstObject;
        [_thumbView setImageFromUrl:[NSURL URLWithString:url].absoluteString placeholderImage:@"placeholder" Blr:YES Shimmering:YES completion:^(UIImage *image) {
            
        }];
    } else {
        _thumbView.image = [UIImage systemImageNamed:@"placeholder"];
    }
}

@end
