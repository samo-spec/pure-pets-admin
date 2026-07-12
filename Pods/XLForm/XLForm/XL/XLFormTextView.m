//
//  XLFormTextView.m
//  XLForm ( https://github.com/xmartlabs/XLForm )
//
//  Copyright (c) 2015 Xmartlabs ( http://xmartlabs.com )
//
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in
// all copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
// THE SOFTWARE.


#import "XLFormTextView.h"

@implementation XLFormTextView

- (void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self name:UITextViewTextDidChangeNotification object:nil];
}

- (instancetype)initWithFrame:(CGRect)frame
{
    if((self = [super initWithFrame:frame])){
        self.scrollsToTop = NO;
        self.contentInset = UIEdgeInsetsMake(0, -4, 0, 0);
        [self setPlaceholder:@""];
        [self setPlaceholderColor:[UIColor colorWithRed:.78 green:.78 blue:.80 alpha:1.0]];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(textChanged:) name:UITextViewTextDidChangeNotification object:nil];
    }
    return self;
}

- (void)textChanged:(NSNotification *)notification
{
    if([[self placeholder] length] == 0){
        return;
    }
    if([[self text] length] == 0){
        [[self viewWithTag:999] setAlpha:1];
    }
    else{
        [[self viewWithTag:999] setAlpha:0];
    }
}

- (void)setText:(NSString *)text {
    // Safety: Handle nil or invalid text gracefully
    if (text == nil) {
        text = @"";  // Convert nil to empty string for safety
    }
    
    // Ensure text is actually a string type
    if (![text isKindOfClass:[NSString class]]) {
        NSLog(@"[XLFormTextView] Warning: setText called with non-string object: %@", NSStringFromClass([text class]));
        text = @"";  // Fall back to empty string
    }
    
    // Call parent implementation with sanitized text
    @try {
        [super setText:text];
    } @catch (NSException *exception) {
        NSLog(@"[XLFormTextView] Exception in setText: %@", exception.reason);
        // Try to set to empty string as fallback
        @try {
            [super setText:@""];
        } @catch (NSException *ex) {
            NSLog(@"[XLFormTextView] Failed to set text even to empty string: %@", ex.reason);
        }
    }
    
    // Safely call textChanged notification handler
    if ([self respondsToSelector:@selector(textChanged:)]) {
        @try {
            [self textChanged:nil];
        } @catch (NSException *exception) {
            NSLog(@"[XLFormTextView] Exception in textChanged: %@", exception.reason);
        }
    }
}

- (void)drawRect:(CGRect)rect
{
    if([[self placeholder] length] > 0){
        if (_placeHolderLabel == nil ){
            UILabel *placeHolderLabel = [[UILabel alloc] initWithFrame:CGRectMake(4,8,self.bounds.size.width - 16,0)];
            placeHolderLabel.lineBreakMode = NSLineBreakByWordWrapping;
            placeHolderLabel.numberOfLines = 0;
            placeHolderLabel.backgroundColor = [UIColor clearColor];
            placeHolderLabel.textColor = self.placeholderColor;
            placeHolderLabel.alpha = 0;
            placeHolderLabel.tag = 999;
            [self addSubview:placeHolderLabel];
            _placeHolderLabel = placeHolderLabel;
        }
        _placeHolderLabel.text = self.placeholder;
        _placeHolderLabel.font = self.font;
        _placeHolderLabel.textColor = self.placeholderColor;
        [_placeHolderLabel sizeToFit];
        [self sendSubviewToBack:_placeHolderLabel];
    }
    if( [[self text] length] == 0 && [[self placeholder] length] > 0 ){
        [[self viewWithTag:999] setAlpha:1];
    }
    [super drawRect:rect];
}

@end
