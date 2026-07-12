//
//  NotificationCell.m
//  PurePetsAdmin
//
//  Created by Mohammed Ahmed on 24/08/2025.
//


// NotificationCell.m
#import "NotificationCell.h"

@implementation NotificationCell {
    UIView *_dot;
    UILabel *_title;
    UILabel *_body;
    UILabel *_time;
}

+ (NSString *)reuseId { return @"NotificationCell"; }

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
    if (self = [super initWithStyle:UITableViewCellStyleDefault reuseIdentifier:reuseIdentifier]) {
        self.backgroundColor = UIColor.systemBackgroundColor;

        _dot = [UIView new]; _dot.translatesAutoresizingMaskIntoConstraints = NO;
        _dot.backgroundColor = [UIColor systemRedColor];
        _dot.layer.cornerRadius = 4;

        _title = [UILabel new]; _title.translatesAutoresizingMaskIntoConstraints = NO;
        _title.font = [UIFont systemFontOfSize:16 weight:UIFontWeightSemibold];

        _body = [UILabel new]; _body.translatesAutoresizingMaskIntoConstraints = NO;
        _body.font = [UIFont systemFontOfSize:14];
        _body.textColor = UIColor.secondaryLabelColor;
        _body.numberOfLines = 2;

        _time = [UILabel new]; _time.translatesAutoresizingMaskIntoConstraints = NO;
        _time.font = [UIFont systemFontOfSize:12 weight:UIFontWeightMedium];
        _time.textColor = UIColor.tertiaryLabelColor;

        UIStackView *v = [[UIStackView alloc] initWithArrangedSubviews:@[_title, _body, _time]];
        v.translatesAutoresizingMaskIntoConstraints = NO;
        v.axis = UILayoutConstraintAxisVertical;
        v.spacing = 2;

        [self.contentView addSubview:_dot];
        [self.contentView addSubview:v];

        [NSLayoutConstraint activateConstraints:@[
            [_dot.widthAnchor constraintEqualToConstant:8],
            [_dot.heightAnchor constraintEqualToConstant:8],
            [_dot.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:16],
            [_dot.centerYAnchor constraintEqualToAnchor:self.contentView.centerYAnchor],

            [v.leadingAnchor constraintEqualToAnchor:_dot.trailingAnchor constant:8],
            [v.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-16],
            [v.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:10],
            [v.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor constant:-10],
        ]];
    }
    return self;
}

- (void)configure:(NotificationModel *)m {
    _dot.hidden = m.isRead;
    _title.text = m.title;
    _body.text  = m.body;

    NSDate *d = m.createdAt ?: [NSDate date];
    NSDateFormatter *fmt = [NSDateFormatter new];
    fmt.dateStyle = NSDateFormatterShortStyle; fmt.timeStyle = NSDateFormatterShortStyle;
    _time.text = [fmt stringFromDate:d];
}
@end