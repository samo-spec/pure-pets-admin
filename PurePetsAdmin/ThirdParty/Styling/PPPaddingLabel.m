//
//  PPPaddingLabel.m
//  PurePetsAdmin
//
//  Created by Mohammed Ahmed on 4/2/26.
//


#import "PPPaddingLabel.h"

@implementation PPPaddingLabel

- (instancetype)init {
    self = [super init];
    if (self) {
        _textInsets = UIEdgeInsetsZero;
    }
    return self;
}

- (void)setTextInsets:(UIEdgeInsets)textInsets {
    _textInsets = textInsets;
    [self setNeedsDisplay];
}

- (void)drawTextInRect:(CGRect)rect {
    [super drawTextInRect:UIEdgeInsetsInsetRect(rect, self.textInsets)];
}

- (CGSize)intrinsicContentSize {
    CGSize size = [super intrinsicContentSize];
    size.width += self.textInsets.left + self.textInsets.right;
    size.height += self.textInsets.top + self.textInsets.bottom;
    return size;
}

@end