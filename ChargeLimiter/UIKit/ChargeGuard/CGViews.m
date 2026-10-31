//
//  CGViews.m
//  ChargeGuard v3.0 — view implementations.
//

#import "CGViews.h"

static UIView *CGCardContainer(void) {
    UIView *view = [[UIView alloc] init];
    view.backgroundColor = [UIColor secondarySystemBackgroundColor];
    view.layer.cornerRadius = 16;
    view.layer.masksToBounds = YES;
    return view;
}

@implementation CGHeroView {
    CAGradientLayer *_gradient;
    UILabel *_percentLabel;
    UILabel *_statusLabel;
    UILabel *_modePill;
    UILabel *_adapterPill;
}

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self != nil) {
        _gradient = [CAGradientLayer layer];
        _gradient.colors = @[(id)[UIColor colorWithRed:0.10 green:0.65 blue:0.45 alpha:1.0].CGColor,
                             (id)[UIColor colorWithRed:0.05 green:0.45 blue:0.75 alpha:1.0].CGColor];
        _gradient.startPoint = CGPointMake(0, 0);
        _gradient.endPoint = CGPointMake(1, 1);
        _gradient.cornerRadius = 20;
        [self.layer insertSublayer:_gradient atIndex:0];
        _percentLabel = [[UILabel alloc] init];
        _percentLabel.font = [UIFont systemFontOfSize:56 weight:UIFontWeightBold];
        _percentLabel.textColor = [UIColor whiteColor];
        _statusLabel = [[UILabel alloc] init];
        _statusLabel.font = [UIFont systemFontOfSize:17 weight:UIFontWeightSemibold];
        _statusLabel.textColor = [UIColor whiteColor];
        _modePill = [[UILabel alloc] init];
        _adapterPill = [[UILabel alloc] init];
        for (UILabel *pill in @[_modePill, _adapterPill]) {
            pill.font = [UIFont systemFontOfSize:13 weight:UIFontWeightSemibold];
            pill.textColor = [UIColor whiteColor];
            pill.backgroundColor = [[UIColor whiteColor] colorWithAlphaComponent:0.22];
            pill.layer.cornerRadius = 12;
            pill.layer.masksToBounds = YES;
            pill.textAlignment = NSTextAlignmentCenter;
        }
        UIStackView *stack = [[UIStackView alloc] initWithArrangedSubviews:@[_percentLabel, _statusLabel]];
        stack.axis = UILayoutConstraintAxisVertical;
        stack.spacing = 4;
        stack.translatesAutoresizingMaskIntoConstraints = NO;
        [self addSubview:stack];
        UIStackView *pills = [[UIStackView alloc] initWithArrangedSubviews:@[_modePill, _adapterPill]];
        pills.axis = UILayoutConstraintAxisHorizontal;
        pills.spacing = 8;
        pills.translatesAutoresizingMaskIntoConstraints = NO;
        [self addSubview:pills];
        [NSLayoutConstraint activateConstraints:@[
            [stack.topAnchor constraintEqualToAnchor:self.topAnchor constant:20],
            [stack.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:20],
            [stack.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-20],
            [pills.topAnchor constraintEqualToAnchor:stack.bottomAnchor constant:16],
            [pills.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:20],
            [pills.bottomAnchor constraintEqualToAnchor:self.bottomAnchor constant:-20],
            [_modePill.heightAnchor constraintEqualToConstant:24],
            [_adapterPill.heightAnchor constraintEqualToConstant:24],
        ]];
    }
    return self;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    _gradient.frame = self.bounds;
}

- (void)updateWithPercentText:(NSString *)percentText
                   statusText:(NSString *)statusText
                modePillText:(NSString *)modePillText
             adapterPillText:(NSString *)adapterPillText
                  isCharging:(BOOL)isCharging {
    _percentLabel.text = percentText;
    _statusLabel.text = isCharging ? [statusText stringByAppendingString:@" ⚡"] : statusText;
    _modePill.text = [NSString stringWithFormat:@"  %@  ", modePillText];
    _adapterPill.text = [NSString stringWithFormat:@"  %@  ", adapterPillText];
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
        _stack.spacing = 10;
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
    title.font = [UIFont systemFontOfSize:13 weight:UIFontWeightMedium];
    title.textColor = [UIColor secondaryLabelColor];
    title.text = item[@"title"];
    UILabel *value = [[UILabel alloc] init];
    value.font = [UIFont systemFontOfSize:20 weight:UIFontWeightBold];
    value.textColor = [UIColor labelColor];
    value.text = item[@"value"];
    UILabel *subtitle = [[UILabel alloc] init];
    subtitle.font = [UIFont systemFontOfSize:12];
    subtitle.textColor = [UIColor secondaryLabelColor];
    subtitle.text = item[@"subtitle"];
    UIStackView *stack = [[UIStackView alloc] initWithArrangedSubviews:@[title, value, subtitle]];
    stack.axis = UILayoutConstraintAxisVertical;
    stack.spacing = 2;
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    [cell addSubview:stack];
    [NSLayoutConstraint activateConstraints:@[
        [stack.topAnchor constraintEqualToAnchor:cell.topAnchor constant:12],
        [stack.leadingAnchor constraintEqualToAnchor:cell.leadingAnchor constant:12],
        [stack.trailingAnchor constraintEqualToAnchor:cell.trailingAnchor constant:-12],
        [stack.bottomAnchor constraintEqualToAnchor:cell.bottomAnchor constant:-12],
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
        row.spacing = 10;
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
        _stack.spacing = 10;
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
        row.spacing = 10;
        row.distribution = UIStackViewDistributionFillEqually;
        for (NSUInteger i = rowStart; i < MIN(rowStart + 2, entries.count); i++) {
            NSDictionary *entry = entries[i];
            UIButton *button = [UIButton buttonWithType:UIButtonTypeCustom];
            button.tag = (NSInteger)i;
            button.backgroundColor = [UIColor secondarySystemBackgroundColor];
            button.layer.cornerRadius = 16;
            button.contentHorizontalAlignment = UIControlContentHorizontalAlignmentLeft;
            button.titleLabel.numberOfLines = 0;
            [button setTitle:[NSString stringWithFormat:@"%@\n%@", entry[@"title"] ?: @"", entry[@"subtitle"] ?: @""] forState:UIControlStateNormal];
            [button setTitleColor:[UIColor labelColor] forState:UIControlStateNormal];
            button.titleLabel.font = [UIFont systemFontOfSize:15 weight:UIFontWeightSemibold];
            button.contentEdgeInsets = UIEdgeInsetsMake(14, 14, 14, 14);
            [button addTarget:self action:@selector(entryTapped:) forControlEvents:UIControlEventTouchUpInside];
            [button.heightAnchor constraintEqualToConstant:88].active = YES;
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
