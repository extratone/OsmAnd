//
//  OATextInfoWidget.m
//  OsmAnd
//
//  Created by Alexey Kulish on 30/09/2017.
//  Copyright © 2017 OsmAnd. All rights reserved.
//

#import "OATextInfoWidget.h"
#import "OAUtilities.h"
#import "OAColors.h"
#import "OAAppSettings.h"
#import "OsmAnd_Maps-Swift.h"

#define textHeight 22
#define imageSide 30
#define minTextWidth 64
#define fullTextWidth 90
#define minWidgetHeight 32


@implementation OATextInfoWidget
{
    NSString *_contentTitle;
    NSString *_text;
    NSString *_subtext;
    BOOL _explicitlyVisible;
    
    NSString *_icon;
    BOOL _isNight;
    
    UIColor *_backgroundColor;
    UIButton *_shadowButton;
    
    UIFont *_largeFont;
    UIFont *_largeBoldFont;
    UIFont *_smallFont;
    UIFont *_smallBoldFont;

    BOOL _metricSystemDepended;
    BOOL _angularUnitsDepended;
    int _cachedMetricSystem;
    int _cachedAngularUnits;
    NSLayoutConstraint *_leadingTextAnchor;
}

- (instancetype) init
{
    self = [super init];

    if (self)
    {
        self.frame = CGRectMake(0, 0, kTextInfoWidgetWidth, kTextInfoWidgetHeight);
        [self initSeparatorView];
    }
    return self;
}

- (instancetype) initWithFrame:(CGRect)frame
{
    self = [super initWithFrame:frame];
    if (self)
    {
        self.frame = CGRectMake(0, 0, kTextInfoWidgetWidth, kTextInfoWidgetHeight);
        [self initSeparatorView];
        [self commonInit];
    }
    
    return self;
}

- (void) commonInit
{
    _textView = [[UILabel alloc] init];
    _textView.adjustsFontForContentSizeCategory = YES;
    _textView.translatesAutoresizingMaskIntoConstraints = NO;
    _textShadowView = [[UILabel alloc] init];
    _textShadowView.adjustsFontForContentSizeCategory = YES;
    _textShadowView.translatesAutoresizingMaskIntoConstraints = NO;
    _imageView = [UIImageView new];
    _imageView.translatesAutoresizingMaskIntoConstraints = NO;

    [self addSubview:_textShadowView];
    [self addSubview:_textView];
    [self addSubview:_imageView];
    
   
    [NSLayoutConstraint activateConstraints:@[
        [_imageView.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:3],
        [_imageView.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
        [_imageView.heightAnchor constraintEqualToConstant:imageSide],
        [_imageView.widthAnchor constraintEqualToConstant:imageSide]
    ]];

    [NSLayoutConstraint activateConstraints:@[
        [_textView.bottomAnchor constraintEqualToAnchor:self.bottomAnchor constant:-5],
        [_textView.trailingAnchor constraintEqualToAnchor:self.trailingAnchor]
    ]];
    self.topTextAnchor = [_textView.topAnchor constraintEqualToAnchor:self.topAnchor constant:5];
    self.topTextAnchor.active = YES;
    
    _leadingTextAnchor = [_textView.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:3];
    _leadingTextAnchor.active = YES;
    
    [NSLayoutConstraint activateConstraints:@[
        [_textShadowView.topAnchor constraintEqualToAnchor:_textView.topAnchor],
        [_textShadowView.bottomAnchor constraintEqualToAnchor:_textView.bottomAnchor],
        [_textShadowView.trailingAnchor constraintEqualToAnchor:_textView.trailingAnchor],
        [_textShadowView.leadingAnchor constraintEqualToAnchor:_textView.leadingAnchor]
    ]];
    
    self.backgroundColor = [UIColor whiteColor];

    _largeFont = [UIFont scaledSystemFontOfSize:21 weight:UIFontWeightSemibold];
    _largeBoldFont = [UIFont scaledSystemFontOfSize:21 weight:UIFontWeightBold];
    _primaryFont = _largeFont;
    _primaryColor = [UIColor blackColor];
    _smallFont = [UIFont scaledSystemFontOfSize:14 weight:UIFontWeightSemibold];
    _smallBoldFont = [UIFont scaledSystemFontOfSize:14 weight:UIFontWeightBold];
    _unitsFont = _smallFont;
    _unitsColor = [UIColor grayColor];
    _primaryShadowColor = nil;
    _unitsShadowColor = nil;
    _shadowRadius = 0;
    
    _text = @"";
    _subtext = @"";
    _textShadowView.textAlignment = NSTextAlignmentNatural;
    _textView.textAlignment = NSTextAlignmentNatural;

    _shadowButton = [[UIButton alloc] initWithFrame:self.frame];
    _shadowButton.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [_shadowButton addTarget:self action:@selector(onWidgetClicked:) forControlEvents:UIControlEventTouchUpInside];
    [self addSubview:_shadowButton];
    
    _metricSystemDepended = NO;
    _angularUnitsDepended = NO;
    _cachedMetricSystem = -1;
    _cachedAngularUnits = -1;
}

- (BOOL)isTextInfo
{
    return YES;
}

- (void) onWidgetClicked:(id)sender
{
    if (self.onClickFunction)
        self.onClickFunction(self);
    
    if (self.delegate)
        [self.delegate widgetClicked:self];
}

- (void) setImage:(UIImage *)image
{
    [_imageView setImage:image];
}

- (void) setImage:(UIImage *)image withColor:(UIColor *)color
{
    [self setImage:image];
    _imageView.tintColor = color;
}

- (void) setImageHidden:(BOOL)hidden
{
    _imageView.hidden = hidden;
}

- (BOOL) setIconForWidgetType:(OAWidgetType *)widgetType
{
    return [self setIcon:widgetType.iconName];
}

- (BOOL) setIcon:(NSString *)widgetIcon
{
    if (![_icon isEqualToString:widgetIcon])
    {
        _icon = widgetIcon;
        [self setImage:[UIImage imageNamed:_icon]];
        return YES;
    }
    else
    {
        return NO;
    }
}

- (BOOL) isNight
{
    return _isNight;
}

- (NSString *) getIconName
{
    return _icon;
}

- (NSString *) combine:(NSString *)text subtext:(NSString *)subtext
{
    if (text.length == 0)
        return subtext;
    else if (subtext.length == 0)
        return text;
    
    return [NSString stringWithFormat:@"%@ %@", text, subtext];
}

- (void) setContentDescription:(NSString *)text
{
    //view.setContentDescription(combine(contentTitle, text));
}

- (void) setContentTitle:(NSString *)text
{
    _contentTitle = text;
    [self setContentDescription:_textView.text];
    _shadowButton.accessibilityLabel = _contentTitle;
}

- (void) setText:(NSString *)text subtext:(NSString *)subtext
{
    [self setTextNoUpdateVisibility:text subtext:subtext];
    [self updateVisibility:text != nil];
}

- (void) setTextNoUpdateVisibility:(NSString *)text subtext:(NSString *)subtext
{
    if ([_text isEqualToString:text] && [subtext isEqualToString:subtext])
        return;
    //        if(this.text != null && this.text.length() > 7) {
    //            this.text = this.text.substring(0, 6) +"..";
    //        }
    if (text.length == 0 && subtext.length == 0)
    {
        _textView.text = @"";
        _text = @"";
        _subtext = @"";
        _shadowButton.accessibilityValue = nil;
    }
    else
    {
        _text = text;
        _subtext = subtext;
        [self refreshLabel];
    }
}

- (void) refreshLabel
{
    NSMutableDictionary<NSAttributedStringKey, id> *attributes = [NSMutableDictionary dictionary];
    if (_imageView.hidden)
    {
        NSMutableParagraphStyle *paragraphStyle = [[NSMutableParagraphStyle alloc] init];
        paragraphStyle.alignment = NSTextAlignmentCenter;
        attributes[NSParagraphStyleAttributeName] = paragraphStyle;
    }
    else
    {
        NSMutableParagraphStyle *ps = [[NSMutableParagraphStyle alloc] init];
        ps.firstLineHeadIndent = 2.0;
        ps.tailIndent = -2.0;
        attributes[NSParagraphStyleAttributeName] = ps;
    }
    NSMutableAttributedString *string = [[NSMutableAttributedString alloc] initWithString:[self combine:_text subtext:_subtext] attributes:attributes];
    NSMutableAttributedString *shadowString = [[NSMutableAttributedString alloc] initWithString:[self combine:_text subtext:_subtext] attributes:attributes];

    NSRange valueRange = NSMakeRange(0, _text.length);
    NSRange unitRange = NSMakeRange(_text.length + 1, _subtext.length);
    
    if (valueRange.length > 0)
    {
        [string addAttribute:NSFontAttributeName value:_primaryFont range:valueRange];
        [string addAttribute:NSForegroundColorAttributeName value:_primaryColor range:valueRange];
        if (_primaryShadowColor && _shadowRadius > 0)
        {
            [shadowString addAttribute:NSFontAttributeName value:_primaryFont range:valueRange];
            [shadowString addAttribute:NSForegroundColorAttributeName value:_primaryColor range:valueRange];
            [shadowString addAttribute:NSStrokeColorAttributeName value:_primaryShadowColor range:valueRange];
            [shadowString addAttribute:NSStrokeWidthAttributeName value:[NSNumber numberWithFloat: -_shadowRadius] range:valueRange];
        }
    }
    if (unitRange.length > 0)
    {
        [string addAttribute:NSFontAttributeName value:_unitsFont range:unitRange];
        [string addAttribute:NSForegroundColorAttributeName value:_unitsColor range:unitRange];
        if (_unitsShadowColor && _shadowRadius > 0)
        {
            [shadowString addAttribute:NSFontAttributeName value:_unitsFont range:unitRange];
            [shadowString addAttribute:NSForegroundColorAttributeName value:_unitsColor range:unitRange];
            [shadowString addAttribute:NSStrokeColorAttributeName value:_unitsShadowColor range:unitRange];
            [shadowString addAttribute:NSStrokeWidthAttributeName value:[NSNumber numberWithFloat: -_shadowRadius] range:unitRange];
        }
    }
    
    _textShadowView.attributedText = _primaryShadowColor && _shadowRadius > 0 ? shadowString : nil;
    _textView.attributedText = string;
    _shadowButton.accessibilityValue = string.string;
    [self refreshLayout];
}

- (void)refreshLayout
{
    if (self.delegate)
        [self.delegate widgetChanged:self];
}

- (void) addAccessibilityLabelsWithValue:(NSString *)value
{
    // override point
}

- (CGFloat) getWidgetHeight
{
    return self.frame.size.height;
}

- (void) adjustViewSize
{
    CGFloat leadingOffset = _imageView.hidden ? 4 : 31;
    _leadingTextAnchor.constant = leadingOffset;
    
    [_textView sizeToFit];
    
    CGRect tf = _textView.frame;
    
    CGFloat currentWidth = MAX(tf.size.width, _imageView.hidden ? fullTextWidth : minTextWidth);
    // TODO: need a more flexible solution for OAUtilities.isLandscapeIpadAware (topWidgetsViewWidthConstraint.constant)
    CGFloat widthLimit = [[OARootViewController instance].mapPanel hasTopWidget] ? 120 : [UIScreen mainScreen].bounds.size.width / 2 - 40;
    tf.size.width = currentWidth > widthLimit ? widthLimit : currentWidth;

    CGRect f = self.frame;
    f.size.width = leadingOffset + tf.size.width + 4;
    CGFloat height = tf.size.height + 10;
    f.size.height = height < minWidgetHeight ? minWidgetHeight : height;
    self.frame = f;
}

- (BOOL) updateVisibility:(BOOL)visible
{
    if (visible == self.hidden)
    {
        self.hidden = !visible;
        if (self.delegate)
            [self.delegate widgetVisibilityChanged:self visible:visible];
        
        return YES;
    }
    return NO;
}

- (BOOL) isVisible
{
    return !self.hidden && self.superview;
}

- (BOOL) updateInfo
{
    if (self.updateInfoFunction)
        return self.updateInfoFunction();
    else
        return NO;
}

- (BOOL) isUpdateNeeded
{
    BOOL res = NO;
    
    if ([self isMetricSystemDepended])
    {
        int metricSystem = (int)[[OAAppSettings sharedManager].metricSystem get];
        res |= _cachedMetricSystem != metricSystem;
        _cachedMetricSystem = metricSystem;
    }
    if ([self isAngularUnitsDepended])
    {
        int angularUnits = (int)[[OAAppSettings sharedManager].angularUnits get];
        res |= _cachedAngularUnits != angularUnits;
        _cachedAngularUnits = angularUnits;
    }
    return res;
}

- (BOOL) isMetricSystemDepended
{
    return _metricSystemDepended;
}

- (BOOL) isAngularUnitsDepended
{
    return _angularUnitsDepended;
}

- (void) setMetricSystemDepended:(BOOL)newValue
{
    _metricSystemDepended = newValue;
}

- (void) setAngularUnitsDepended:(BOOL)newValue
{
    _angularUnitsDepended = newValue;
}

- (void) setExplicitlyVisible:(BOOL)explicitlyVisible
{
    _explicitlyVisible = explicitlyVisible;
}

- (BOOL) isExplicitlyVisible
{
    return _explicitlyVisible;
}

- (void) setTimeText:(NSTimeInterval)time
{
    int hours, minutes, seconds;
    [OAUtilities getHMS:time hours:&hours minutes:&minutes seconds:&seconds];
    NSString *timeStr = [NSString stringWithFormat:@"%d:%02d", hours, minutes];
    [self setText:timeStr subtext:nil];
}

- (void) updateIconMode:(BOOL)night
{
    _isNight = night;
    _imageView.overrideUserInterfaceStyle = night ? UIUserInterfaceStyleDark : UIUserInterfaceStyleLight;
    if (_icon)
        [self setImage:[UIImage imageNamed:_icon]];
}

- (void) updateTextColor:(UIColor *)textColor textShadowColor:(UIColor *)textShadowColor bold:(BOOL)bold shadowRadius:(float)shadowRadius
{
    if (bold)
    {
        _primaryFont = _largeBoldFont;
        _unitsFont = _smallBoldFont;
    }
    else
    {
        _primaryFont = _largeFont;
        _unitsFont = _smallFont;
    }
    
    _primaryColor = textColor;
    _unitsColor = textColor;
    _primaryShadowColor = textShadowColor;
    _unitsShadowColor = textShadowColor;
    _shadowRadius = shadowRadius;

    [self refreshLabel];
}

@end
