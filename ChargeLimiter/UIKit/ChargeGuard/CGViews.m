//
//  CGViews.m
//  ChargeGuard v3.0 — view implementations.
//
//  iOS 27 Liquid Glass look, back-ported to UIKit (iOS 13+ APIs only, so
//  it still builds for the iOS 16.5 device): frosted-glass cards with a
//  hairline highlight edge and a soft drop shadow, large 28–32pt radii,
//  and a gradient battery ring on the hero instead of a solid colour
//  block. Views only render; they never call the daemon.
//

#import "CGViews.h"
#import <math.h>

// Shared glass card: a blur layer first, so anything added later sits
// on top of the frosted surface. Highlight edge + soft shadow give the
// glass depth; the blur itself adapts to light/dark mode.
@implementation CGGlassView {
    UIVisualEffectView *_blur;
}

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self != nil) {
        self.backgroundColor = [UIColor clearColor];
        self.layer.cornerRadius = 28;
        self.layer.borderWidth = 0.5;
        self.layer.borderColor = [[UIColor whiteColor] colorWithAlphaComponent:0.45].CGColor;
        self.layer.shadowColor = [UIColor blackColor].CGColor;
        self.layer.shadowOpacity = 0.10;
        self.layer.shadowRadius = 18;
        self.layer.shadowOffset = CGSizeMake(0, 10);
        _blur = [[UIVisualEffectView alloc] initWithEffect:[UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemUltraThinMaterial]];
        _blur.layer.cornerRadius = 28;
        _blur.clipsToBounds = YES;
        _blur.translatesAutoresizingMaskIntoConstraints = NO;
        [self addSubview:_blur];
        [NSLayoutConstraint activateConstraints:@[
            [_blur.topAnchor constraintEqualToAnchor:self.topAnchor],
            [_blur.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
            [_blur.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
            [_blur.bottomAnchor constraintEqualToAnchor:self.bottomAnchor],
        ]];
    }
    return self;
}

@end

static UIView *CGCardContainer(void) {
    return [[CGGlassView alloc] init];
}

static UILabel *CGPillLabel(void) {
    UILabel *pill = [[UILabel alloc] init];
    pill.font = [UIFont systemFontOfSize:13 weight:UIFontWeightSemibold];
    pill.textColor = [UIColor labelColor];
    pill.backgroundColor = [UIColor tertiarySystemFillColor];
    pill.layer.cornerRadius = 14;
    pill.layer.masksToBounds = YES;
    pill.textAlignment = NSTextAlignmentCenter;
    return pill;
}

@implementation CGHeroView {
    CGGlassView *_glass;
    CAGradientLayer *_ringGradient;
    CAShapeLayer *_ringTrack;
    CAShapeLayer *_ringProgress;
    UIView *_ringView;
    UILabel *_ringCenterLabel;
    UILabel *_percentLabel;
    UILabel *_statusLabel;
    UILabel *_modePill;
    UILabel *_adapterPill;
    CGFloat _percent;
    BOOL _isCharging;
}

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self != nil) {
        self.backgroundColor = [UIColor clearColor];
        _glass = [[CGGlassView alloc] init];
        _glass.layer.cornerRadius = 32;
        _glass.translatesAutoresizingMaskIntoConstraints = NO;
        [self addSubview:_glass];
        [NSLayoutConstraint activateConstraints:@[
            [_glass.topAnchor constraintEqualToAnchor:self.topAnchor],
            [_glass.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
            [_glass.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
            [_glass.bottomAnchor constraintEqualToAnchor:self.bottomAnchor],
        ]];
        // Fix the glass blur's own radius to match the hero.
        for (UIView *sub in _glass.subviews) {
            if ([sub isKindOfClass:[UIVisualEffectView class]]) {
                sub.layer.cornerRadius = 32;
            }
        }

        _percentLabel = [[UILabel alloc] init];
        _percentLabel.font = [UIFont systemFontOfSize:64 weight:UIFontWeightHeavy];
        _percentLabel.textColor = [UIColor labelColor];
        _statusLabel = [[UILabel alloc] init];
        _statusLabel.font = [UIFont systemFontOfSize:16 weight:UIFontWeightSemibold];
        _statusLabel.textColor = [UIColor secondaryLabelColor];
        _modePill = CGPillLabel();
        _adapterPill = CGPillLabel();

        UIStackView *textStack = [[UIStackView alloc] initWithArrangedSubviews:@[_percentLabel, _statusLabel]];
        textStack.axis = UILayoutConstraintAxisVertical;
        textStack.spacing = 2;
        textStack.translatesAutoresizingMaskIntoConstraints = NO;

        UIStackView *pills = [[UIStackView alloc] initWithArrangedSubviews:@[_modePill, _adapterPill]];
        pills.axis = UILayoutConstraintAxisHorizontal;
        pills.spacing = 8;
        pills.translatesAutoresizingMaskIntoConstraints = NO;

        UIStackView *leftStack = [[UIStackView alloc] initWithArrangedSubviews:@[textStack, pills]];
        leftStack.axis = UILayoutConstraintAxisVertical;
        leftStack.spacing = 14;
        leftStack.translatesAutoresizingMaskIntoConstraints = NO;

        // Battery ring: gradient stroke over a faint track, drawn with
        // CAGradientLayer masked by the progress shape.
        _ringView = [[UIView alloc] init];
        _ringView.translatesAutoresizingMaskIntoConstraints = NO;
        _ringTrack = [CAShapeLayer layer];
        _ringTrack.strokeColor = [UIColor systemGray5Color].CGColor;
        _ringTrack.fillColor = [UIColor clearColor].CGColor;
        _ringTrack.lineWidth = 11;
        _ringTrack.lineCap = kCALineCapRound;
        [_ringView.layer addSublayer:_ringTrack];
        _ringProgress = [CAShapeLayer layer];
        _ringProgress.strokeColor = [UIColor blackColor].CGColor;
        _ringProgress.fillColor = [UIColor clearColor].CGColor;
        _ringProgress.lineWidth = 11;
        _ringProgress.lineCap = kCALineCapRound;
        _ringGradient = [CAGradientLayer layer];
        _ringGradient.colors = @[(id)[UIColor colorWithRed:0.20 green:0.85 blue:0.55 alpha:1.0].CGColor,
                                 (id)[UIColor colorWithRed:0.10 green:0.75 blue:0.75 alpha:1.0].CGColor,
                                 (id)[UIColor colorWithRed:0.20 green:0.55 blue:0.95 alpha:1.0].CGColor];
        _ringGradient.startPoint = CGPointMake(0, 0);
        _ringGradient.endPoint = CGPointMake(1, 1);
        _ringGradient.mask = _ringProgress;
        [_ringView.layer addSublayer:_ringGradient];
        _ringCenterLabel = [[UILabel alloc] init];
        _ringCenterLabel.font = [UIFont systemFontOfSize:28 weight:UIFontWeightBold];
        _ringCenterLabel.textColor = [UIColor systemGreenColor];
        _ringCenterLabel.textAlignment = NSTextAlignmentCenter;
        _ringCenterLabel.translatesAutoresizingMaskIntoConstraints = NO;
        [_ringView addSubview:_ringCenterLabel];
        [NSLayoutConstraint activateConstraints:@[
            [_ringCenterLabel.centerXAnchor constraintEqualToAnchor:_ringView.centerXAnchor],
            [_ringCenterLabel.centerYAnchor constraintEqualToAnchor:_ringView.centerYAnchor],
            [_ringView.widthAnchor constraintEqualToConstant:92],
            [_ringView.heightAnchor constraintEqualToConstant:92],
        ]];

        [_glass addSubview:leftStack];
        [_glass addSubview:_ringView];
        [NSLayoutConstraint activateConstraints:@[
            [leftStack.leadingAnchor constraintEqualToAnchor:_glass.leadingAnchor constant:22],
            [leftStack.centerYAnchor constraintEqualToAnchor:_glass.centerYAnchor],
            [_ringView.leadingAnchor constraintEqualToAnchor:leftStack.trailingAnchor constant:12],
            [_ringView.trailingAnchor constraintEqualToAnchor:_glass.trailingAnchor constant:-22],
            [_ringView.centerYAnchor constraintEqualToAnchor:_glass.centerYAnchor],
            [_modePill.heightAnchor constraintEqualToConstant:28],
            [_adapterPill.heightAnchor constraintEqualToConstant:28],
        ]];
    }
    return self;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGRect bounds = _ringView.bounds;
    CGFloat radius = (MIN(bounds.size.width, bounds.size.height) - 11) / 2.0;
    CGPoint center = CGPointMake(bounds.size.width / 2.0, bounds.size.height / 2.0);
    UIBezierPath *circle = [UIBezierPath bezierPathWithArcCenter:center radius:radius startAngle:-M_PI_2 endAngle:(3 * M_PI_2) clockwise:YES];
    _ringTrack.path = circle.CGPath;
    _ringProgress.path = circle.CGPath;
    _ringProgress.strokeEnd = MAX(0, MIN(1, _percent / 100.0));
    _ringGradient.frame = bounds;
}

- (void)updateWithPercentText:(NSString *)percentText
                   statusText:(NSString *)statusText
                modePillText:(NSString *)modePillText
             adapterPillText:(NSString *)adapterPillText
                  isCharging:(BOOL)isCharging {
    _percentLabel.text = percentText;
    _percent = [percentText integerValue];
    _isCharging = isCharging;
    _statusLabel.text = statusText;
    _ringCenterLabel.text = isCharging ? @"⚡" : @"";
    _modePill.text = [NSString stringWithFormat:@"  %@  ", modePillText];
    _adapterPill.text = [NSString stringWithFormat:@"  %@  ", adapterPillText];
    [self setNeedsLayout];
}

@end

@implementation CGStatGridView {
    UIStackView *_stack;
}

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self != nil) {
        _stack = [[UIStackView alloc] init];
        _stack.axis = UILayoutConstraintAxisVertical;
        _stack.spacing = 12;
        _stack.translatesAutoresizingMaskIntoConstraints = NO;
        [self addSubview:_stack];
        [NSLayoutConstraint activateConstraints:@[
            [_stack.topAnchor constraintEqualToAnchor:self.topAnchor],
            [_stack.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
            [_stack.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
            [_stack.bottomAnchor constraintEqualToAnchor:self.bottomAnchor],
        ]];
    }
    return self;
}

- (UIView *)cellForItem:(NSDictionary *)item {
    UIView *cell = CGCardContainer();
    UILabel *title = [[UILabel alloc] init];
    title.font = [UIFont systemFontOfSize:12 weight:UIFontWeightMedium];
    title.textColor = [UIColor secondaryLabelColor];
    title.text = item[@"title"];
    UILabel *value = [[UILabel alloc] init];
    value.font = [UIFont systemFontOfSize:22 weight:UIFontWeightBold];
    value.textColor = [UIColor labelColor];
    value.text = item[@"value"];
    UILabel *subtitle = [[UILabel alloc] init];
    subtitle.font = [UIFont systemFontOfSize:12];
    subtitle.textColor = [UIColor secondaryLabelColor];
    subtitle.text = item[@"subtitle"];
    UIStackView *stack = [[UIStackView alloc] initWithArrangedSubviews:@[title, value, subtitle]];
    stack.axis = UILayoutConstraintAxisVertical;
    stack.spacing = 3;
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    [cell addSubview:stack];
    [NSLayoutConstraint activateConstraints:@[
        [stack.topAnchor constraintEqualToAnchor:cell.topAnchor constant:14],
        [stack.leadingAnchor constraintEqualToAnchor:cell.leadingAnchor constant:16],
        [stack.trailingAnchor constraintEqualToAnchor:cell.trailingAnchor constant:-16],
        [stack.bottomAnchor constraintEqualToAnchor:cell.bottomAnchor constant:-14],
    ]];
    return cell;
}

- (void)updateWithItems:(NSArray<NSDictionary *> *)items {
    for (UIView *view in _stack.arrangedSubviews) {
        [_stack removeArrangedSubview:view];
        [view removeFromSuperview];
    }
    for (NSUInteger rowStart = 0; rowStart < items.count; rowStart += 2) {
        UIStackView *row = [[UIStackView alloc] init];
        row.axis = UILayoutConstraintAxisHorizontal;
        row.spacing = 12;
        row.distribution = UIStackViewDistributionFillEqually;
        [row addArrangedSubview:[self cellForItem:items[rowStart]]];
        if (rowStart + 1 < items.count) {
            [row addArrangedSubview:[self cellForItem:items[rowStart + 1]]];
        }
        [_stack addArrangedSubview:row];
    }
}

@end

@implementation CGEntryGridView {
    UIStackView *_stack;
    void (^_tapHandler)(NSInteger index);
}

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self != nil) {
        _stack = [[UIStackView alloc] init];
        _stack.axis = UILayoutConstraintAxisVertical;
        _stack.spacing = 12;
        _stack.translatesAutoresizingMaskIntoConstraints = NO;
        [self addSubview:_stack];
        [NSLayoutConstraint activateConstraints:@[
            [_stack.topAnchor constraintEqualToAnchor:self.topAnchor],
            [_stack.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
            [_stack.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
            [_stack.bottomAnchor constraintEqualToAnchor:self.bottomAnchor],
        ]];
    }
    return self;
}

- (void)entryTapped:(UIButton *)sender {
    if (_tapHandler != nil) {
        _tapHandler(sender.tag);
    }
}

- (void)updateWithEntries:(NSArray<NSDictionary *> *)entries
               tapHandler:(void (^)(NSInteger index))tapHandler {
    _tapHandler = [tapHandler copy];
    for (UIView *view in _stack.arrangedSubviews) {
        [_stack removeArrangedSubview:view];
        [view removeFromSuperview];
    }
    for (NSUInteger rowStart = 0; rowStart < entries.count; rowStart += 2) {
        UIStackView *row = [[UIStackView alloc] init];
        row.axis = UILayoutConstraintAxisHorizontal;
        row.spacing = 12;
        row.distribution = UIStackViewDistributionFillEqually;
        for (NSUInteger i = rowStart; i < MIN(rowStart + 2, entries.count); i++) {
            NSDictionary *entry = entries[i];
            UIButton *button = [UIButton buttonWithType:UIButtonTypeCustom];
            button.tag = (NSInteger)i;
            button.backgroundColor = [UIColor clearColor];
            button.layer.cornerRadius = 28;
            button.layer.borderWidth = 0.5;
            button.layer.borderColor = [[UIColor whiteColor] colorWithAlphaComponent:0.45].CGColor;
            button.layer.shadowColor = [UIColor blackColor].CGColor;
            button.layer.shadowOpacity = 0.10;
            button.layer.shadowRadius = 18;
            button.layer.shadowOffset = CGSizeMake(0, 10);
            button.contentHorizontalAlignment = UIControlContentHorizontalAlignmentLeft;
            button.titleLabel.numberOfLines = 0;
            // Glass behind the title: blur first, title sits on top.
            UIVisualEffectView *blur = [[UIVisualEffectView alloc] initWithEffect:[UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemUltraThinMaterial]];
            blur.layer.cornerRadius = 28;
            blur.clipsToBounds = YES;
            blur.userInteractionEnabled = NO;
            blur.translatesAutoresizingMaskIntoConstraints = NO;
            [button insertSubview:blur atIndex:0];
            [NSLayoutConstraint activateConstraints:@[
                [blur.topAnchor constraintEqualToAnchor:button.topAnchor],
                [blur.leadingAnchor constraintEqualToAnchor:button.leadingAnchor],
                [blur.trailingAnchor constraintEqualToAnchor:button.trailingAnchor],
                [blur.bottomAnchor constraintEqualToAnchor:button.bottomAnchor],
            ]];
            // Two-tone title: bold title line, grey subtitle line. The
            // old single-font "title\nsubtitle" is what looked flat.
            NSString *title = entry[@"title"] ?: @"";
            NSString *subtitle = entry[@"subtitle"] ?: @"";
            NSMutableAttributedString *text = [[NSMutableAttributedString alloc] init];
            [text appendAttributedString:[[NSAttributedString alloc] initWithString:title attributes:@{
                NSFontAttributeName: [UIFont systemFontOfSize:16 weight:UIFontWeightSemibold],
                NSForegroundColorAttributeName: [UIColor labelColor],
            }]];
            if (subtitle.length > 0) {
                [text appendAttributedString:[[NSAttributedString alloc] initWithString:[NSString stringWithFormat:@"\n%@", subtitle] attributes:@{
                    NSFontAttributeName: [UIFont systemFontOfSize:12.5 weight:UIFontWeightRegular],
                    NSForegroundColorAttributeName: [UIColor secondaryLabelColor],
                }]];
            }
            [button setAttributedTitle:text forState:UIControlStateNormal];
            button.contentEdgeInsets = UIEdgeInsetsMake(16, 16, 16, 16);
            [button addTarget:self action:@selector(entryTapped:) forControlEvents:UIControlEventTouchUpInside];
            [button.heightAnchor constraintEqualToConstant:96].active = YES;
            [row addArrangedSubview:button];
        }
        [_stack addArrangedSubview:row];
    }
}

@end

@implementation CGCapsuleFilterView {
    UISegmentedControl *_control;
    void (^_changeHandler)(NSInteger index);
}

- (instancetype)initWithTitles:(NSArray<NSString *> *)titles
                selectedIndex:(NSInteger)selectedIndex
                  changeHandler:(void (^)(NSInteger index))changeHandler {
    self = [super initWithFrame:CGRectZero];
    if (self != nil) {
        _changeHandler = [changeHandler copy];
        _control = [[UISegmentedControl alloc] initWithItems:titles];
        _control.selectedSegmentIndex = selectedIndex;
        _control.translatesAutoresizingMaskIntoConstraints = NO;
        [_control addTarget:self action:@selector(segmentChanged:) forControlEvents:UIControlEventValueChanged];
        [self addSubview:_control];
        [NSLayoutConstraint activateConstraints:@[
            [_control.topAnchor constraintEqualToAnchor:self.topAnchor],
            [_control.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
            [_control.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
            [_control.bottomAnchor constraintEqualToAnchor:self.bottomAnchor],
        ]];
    }
    return self;
}

- (NSInteger)selectedIndex {
    return _control.selectedSegmentIndex;
}

- (void)segmentChanged:(UISegmentedControl *)sender {
    if (_changeHandler != nil) {
        _changeHandler(sender.selectedSegmentIndex);
    }
}

@end
