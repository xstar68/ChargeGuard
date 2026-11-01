//
//  CGSubPages.m
//  ChargeGuard v3.0 — sub-page implementations (deep redo, 2026-11-01).
//
//  Every page below is complete in itself. It reads and writes through
//  CGDaemonClient (the sole daemon interface) and, for app-local settings,
//  through CLBatteryManager / the shared local store. No page routes to
//  a legacy page. The compat page reuses the real compat engine (forward
//  declared, same object the old page used) instead of re-implementing
//  its probe/restore logic — duplicating that engine would risk changing
//  stop-charge behaviour, which this redo must not do.
//

#import "CGSubPages.h"
#import "CGConfig.h"
#import "CGDaemonClient.h"
#import "CGHistoryAnalytics.h"
#import "CGPresetManager.h"
#import "CGDiagnosticsExporter.h"
#import "CGViews.h"
#import "../CLBatteryManager.h"
#import "../../CLLocalization.h"

// Shared local store (declared in the old settings file, implemented in
// utils.mm; forward declared here so this file does not drag utils.h in).
id getlocalKV_C(NSString *key);
void setlocalKV_C(NSString *key, id val);
NSString *getRuntimeDataRootPath_C(void);
NSString *getAppDocumentsPath_C(void);
NSArray<NSString *> *getLegacyConfigDirsWithData_C(void);
NSDictionary *migrateLegacyConfigFiles_C(void);
NSDictionary *cleanupLegacyResidualFiles_C(void);

// Compat engine (implemented in the old compat file; forward declared
// here so the new page runs the real engine in-page).
typedef NS_ENUM(NSInteger, CGCompatTestKind) { CGCompatTestKindStop = 0, CGCompatTestKindSmart = 1, CGCompatTestKindInflow = 2 };
typedef NS_ENUM(NSInteger, CGCompatTestVerdict) { CGCompatTestVerdictPending = 0, CGCompatTestVerdictSupported = 1, CGCompatTestVerdictUnsupported = 2, CGCompatTestVerdictError = 3 };
typedef NS_ENUM(NSInteger, CGCompatEventKind) { CGCompatEventKindPhase = 0, CGCompatEventKindSample = 1, CGCompatEventKindState = 2, CGCompatEventKindVerdict = 3, CGCompatEventKindFinished = 4, CGCompatEventKindAborted = 5 };
typedef NS_ENUM(NSInteger, CGCompatInflowRestoreMode) { CGCompatRestoreNone = 0, CGCompatRestoreSystem = 1, CGCompatRestoreAfterRelease = 2 };
@interface CLCompatTestEvent : NSObject
@property (nonatomic, assign) CGCompatEventKind kind;
@property (nonatomic, assign) CGCompatTestKind testKind;
@property (nonatomic, copy, nullable) NSString *message;
@property (nonatomic, assign) NSInteger currentmA;
@property (nonatomic, assign) NSTimeInterval elapsed;
@property (nonatomic, assign) double progress;
@property (nonatomic, assign) CGCompatTestVerdict verdict;
@property (nonatomic, assign) NSInteger maxCurrentmA;
@property (nonatomic, assign) NSInteger minCurrentmA;
@property (nonatomic, assign) NSTimeInterval exitElapsed;
@property (nonatomic, assign) NSTimeInterval returnElapsed;
@property (nonatomic, assign) CGCompatInflowRestoreMode restoreMode;
@end
// The engine class is compiled from the old compat file under this name.
@interface CLBatteryCompatibilityEngine : NSObject
@property (nonatomic, copy, nullable) void (^onEvent)(CLCompatTestEvent *event);
- (void)startWithSelection:(NSArray<NSNumber *> *)selection;
- (void)cancel;
+ (void)runPrecheckWithCompletion:(void (^)(NSDictionary<NSString *, NSNumber *> *results))completion;
+ (void)writeSnapshotWithCompletion:(void (^)(BOOL ok))completion;
+ (void)clearSnapshot;
+ (void)restoreSnapshot:(BOOL)alsoRestoreCharging completion:(nullable void (^)(BOOL ok))completion;
+ (BOOL)hasPendingSnapshot;
@end

#pragma mark - Shared helpers

static void CGShowAlert(UIViewController *vc, NSString *title, NSString *message) {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:title message:message preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleDefault handler:nil]];
    [vc presentViewController:alert animated:YES completion:nil];
}

static UIButton *CGTextButton(NSString *title, id target, SEL action) {
    UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
    button.titleLabel.numberOfLines = 1;
    button.titleLabel.adjustsFontSizeToFitWidth = YES;
    button.titleLabel.textAlignment = NSTextAlignmentCenter;
    [button setTitle:title forState:UIControlStateNormal];
    button.titleLabel.font = [UIFont systemFontOfSize:16 weight:UIFontWeightSemibold];
    [button addTarget:target action:action forControlEvents:UIControlEventTouchUpInside];
    return button;
}

static UIButton *CGBackButton(id target, SEL action) {
    UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
    button.contentHorizontalAlignment = UIControlContentHorizontalAlignmentLeft;
    [button setTitle:@"‹ 返回" forState:UIControlStateNormal];
    button.titleLabel.font = [UIFont systemFontOfSize:16 weight:UIFontWeightSemibold];
    [button addTarget:target action:action forControlEvents:UIControlEventTouchUpInside];
    return button;
}

static UILabel *CGCardLabel(NSString *text, CGFloat size, UIFontWeight weight, UIColor *color) {
    UILabel *label = [[UILabel alloc] init];
    label.font = [UIFont systemFontOfSize:size weight:weight];
    label.textColor = color;
    label.numberOfLines = 0;
    label.text = text;
    return label;
}

static UILabel *CGSingleLineLabel(NSString *text, CGFloat size, UIFontWeight weight, UIColor *color) {
    UILabel *label = [[UILabel alloc] init];
    label.font = [UIFont systemFontOfSize:size weight:weight];
    label.textColor = color;
    label.numberOfLines = 1;
    label.adjustsFontSizeToFitWidth = YES;
    label.minimumScaleFactor = 0.75;
    label.text = text;
    return label;
}

static UIView *CGCardWithStack(UIStackView *stack) {
    UIView *card = [[CGGlassView alloc] init];
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    [card addSubview:stack];
    [NSLayoutConstraint activateConstraints:@[
        [stack.topAnchor constraintEqualToAnchor:card.topAnchor constant:20],
        [stack.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:20],
        [stack.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-20],
        [stack.bottomAnchor constraintEqualToAnchor:card.bottomAnchor constant:-20],
    ]];
    return card;
}

static UIStackView *CGVerticalStack(NSArray<UIView *> *views) {
    UIStackView *stack = [[UIStackView alloc] initWithArrangedSubviews:views];
    stack.axis = UILayoutConstraintAxisVertical;
    stack.spacing = 12;
    return stack;
}

static void CGAddScrollStack(UIViewController *vc, UIStackView *stack) {
    UIScrollView *scroll = [[UIScrollView alloc] init];
    scroll.translatesAutoresizingMaskIntoConstraints = NO;
    [vc.view addSubview:scroll];
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    [scroll addSubview:stack];
    [NSLayoutConstraint activateConstraints:@[
        [scroll.topAnchor constraintEqualToAnchor:vc.view.topAnchor],
        [scroll.leadingAnchor constraintEqualToAnchor:vc.view.leadingAnchor],
        [scroll.trailingAnchor constraintEqualToAnchor:vc.view.trailingAnchor],
        [scroll.bottomAnchor constraintEqualToAnchor:vc.view.bottomAnchor],
        [stack.topAnchor constraintEqualToAnchor:scroll.topAnchor constant:8],
        [stack.leadingAnchor constraintEqualToAnchor:scroll.leadingAnchor constant:20],
        [stack.trailingAnchor constraintEqualToAnchor:scroll.trailingAnchor constant:-20],
        [stack.bottomAnchor constraintEqualToAnchor:scroll.bottomAnchor constant:-40],
        [stack.widthAnchor constraintEqualToAnchor:scroll.widthAnchor constant:-40],
    ]];
}

static UIView *CGSwitchRow(NSString *title, NSString *subtitle, UISwitch *sw) {
    UILabel *titleLabel = CGSingleLineLabel(title, 16, UIFontWeightSemibold, [UIColor labelColor]);
    UILabel *subtitleLabel = CGCardLabel(subtitle, 13, UIFontWeightRegular, [UIColor secondaryLabelColor]);
    UIStackView *texts = CGVerticalStack(@[titleLabel, subtitleLabel]);
    texts.spacing = 2;
    UIStackView *row = [[UIStackView alloc] initWithArrangedSubviews:@[texts, sw]];
    row.axis = UILayoutConstraintAxisHorizontal;
    row.spacing = 12;
    row.alignment = UIStackViewAlignmentCenter;
    return row;
}

// Tappable value row: title left (single line), value right (single line,
// truncated at the tail — never wrapped mid-word). The overlay button
// carries the caller's tag/action.
static UIView *CGValueRow(NSString *title, NSString *value, id target, SEL action, NSInteger tag, NSMutableDictionary<NSString *, UILabel *> *valueLabels, NSString *valueKey) {
    UILabel *titleLabel = CGSingleLineLabel(title, 16, UIFontWeightSemibold, [UIColor labelColor]);
    UILabel *valueLabel = [[UILabel alloc] init];
    valueLabel.font = [UIFont systemFontOfSize:15 weight:UIFontWeightRegular];
    valueLabel.textColor = [UIColor secondaryLabelColor];
    valueLabel.numberOfLines = 1;
    valueLabel.lineBreakMode = NSLineBreakByTruncatingTail;
    valueLabel.textAlignment = NSTextAlignmentRight;
    valueLabel.text = value ?: @"—";
    UIStackView *row = [[UIStackView alloc] initWithArrangedSubviews:@[titleLabel, valueLabel]];
    row.axis = UILayoutConstraintAxisHorizontal;
    row.spacing = 12;
    row.alignment = UIStackViewAlignmentCenter;
    if (target != nil && action != NULL) {
        UIButton *overlay = [UIButton buttonWithType:UIButtonTypeCustom];
        overlay.translatesAutoresizingMaskIntoConstraints = NO;
        overlay.tag = tag;
        [overlay addTarget:target action:action forControlEvents:UIControlEventTouchUpInside];
        [row addSubview:overlay];
        [NSLayoutConstraint activateConstraints:@[
            [overlay.topAnchor constraintEqualToAnchor:row.topAnchor],
            [overlay.leadingAnchor constraintEqualToAnchor:row.leadingAnchor],
            [overlay.trailingAnchor constraintEqualToAnchor:row.trailingAnchor],
            [overlay.bottomAnchor constraintEqualToAnchor:row.bottomAnchor],
        ]];
    }
    if (valueLabels != nil && valueKey != nil) {
        valueLabels[valueKey] = valueLabel;
    }
    return row;
}

static BOOL CGBoolFromRaw(NSDictionary *raw, NSString *key, BOOL fallback) {
    id value = raw[key];
    if (value == nil) {
        return fallback;
    }
    if ([value respondsToSelector:@selector(boolValue)]) {
        return [value boolValue];
    }
    return fallback;
}

static NSInteger CGIntFromRaw(NSDictionary *raw, NSString *key, NSInteger fallback) {
    id value = raw[key];
    if (value == nil) {
        return fallback;
    }
    if ([value respondsToSelector:@selector(integerValue)]) {
        return [value integerValue];
    }
    return fallback;
}

// Policy events: the real state lives in to/state/policyState, reason is a
// reason code. Anything unmapped falls back to a plain sentence — never
// "?" and never a raw English code.
static NSString *CGPolicyEventText(NSDictionary *event) {
    NSString *candidate = event[@"to"];
    if (![candidate isKindOfClass:[NSString class]] || candidate.length == 0 || [candidate isEqualToString:@"?"]) {
        candidate = event[@"state"];
    }
    if (![candidate isKindOfClass:[NSString class]] || candidate.length == 0 || [candidate isEqualToString:@"?"]) {
        candidate = event[@"policyState"];
    }
    if (![candidate isKindOfClass:[NSString class]] || candidate.length == 0 || [candidate isEqualToString:@"?"]) {
        candidate = event[@"reason"];
    }
    NSDictionary *map = @{
        @"battery_idle": @"电池空闲",
        @"battery": @"使用电池",
        @"charging": @"正在充电",
        @"charging_active": @"正在充电",
        @"external_idle": @"外部电源空闲",
        @"plug_mode_start": @"开始插电模式",
        @"plug": @"已插电",
        @"hold": @"保持停充",
        @"hold_recharge": @"保持后恢复充电",
        @"hold_target_reached": @"达到停充目标",
        @"hold_band_lower_reached": @"低于保持区间，开始补电",
        @"stop": @"已停充",
        @"inhibit": @"已停充",
        @"resume": @"恢复充电",
        @"temperature_high": @"温度过高，暂停充电",
        @"temperature_hysteresis": @"温度回落，恢复充电",
        @"temperature_recovered": @"温度恢复，恢复充电",
        @"capacity_high": @"电量达到上限，停充",
        @"capacity_low": @"电量回落，恢复充电",
        @"smart_charge_on": @"系统优化充电已接管",
        @"smart_charge_off": @"系统优化充电已退出",
        @"edge_mode_stop": @"边缘触发停充",
    };
    NSString *text = map[candidate];
    if (text != nil) {
        return text;
    }
    // Events typed as hold / smart-charge / thermal carry their meaning in
    // the type field even when the state field is empty.
    NSString *type = event[@"type"];
    if ([type isKindOfClass:[NSString class]]) {
        if ([type containsString:@"hold"]) {
            return @"保持状态变化";
        }
        if ([type containsString:@"smart"]) {
            return @"系统优化充电状态变化";
        }
        if ([type containsString:@"thermal"] || [type containsString:@"temperature"]) {
            return @"温度控制状态变化";
        }
    }
    return @"策略变化";
}

static NSString *CGThermalModeName(NSInteger mode) {
    switch (mode) {
        case 0: return @"关闭";
        case 1: return @"正常";
        case 2: return @"轻度";
        case 3: return @"中度";
        case 4: return @"重度";
        default: return @"关闭";
    }
}

static NSString *CGThermalModeValue(NSInteger mode) {
    switch (mode) {
        case 0: return @"off";
        case 1: return @"nominal";
        case 2: return @"light";
        case 3: return @"moderate";
        case 4: return @"heavy";
        default: return @"off";
    }
}

static NSInteger CGThermalModeFromValue(id value) {
    NSString *s = [value isKindOfClass:[NSString class]] ? value : @"";
    if ([s isEqualToString:@"nominal"]) return 1;
    if ([s isEqualToString:@"light"]) return 2;
    if ([s isEqualToString:@"moderate"]) return 3;
    if ([s isEqualToString:@"heavy"]) return 4;
    return 0;
}

static NSString *CGProbePathName(NSString *service, NSString *path, NSInteger index) {
    // Probe payloads name daemon internals (service/path). The UI shows a
    // human name; unknown paths get a numbered name, never the raw code.
    if (service != nil && [service containsString:@"SmartBattery"]) {
        return @"系统电池管理";
    }
    if (service != nil && [service containsString:@"PowerSource"]) {
        return @"电源管理";
    }
    if (path != nil && [path containsString:@"IsCharging"]) {
        return @"充电开关";
    }
    if (path != nil && [path containsString:@"Inhibit"]) {
        return @"停充抑制";
    }
    return [NSString stringWithFormat:@"停充路径 %ld", (long)(index + 1)];
}

static NSString *CGProbeVerdictText(NSDictionary *item) {
    NSString *verdict = item[@"verdict"];
    if ([verdict isKindOfClass:[NSString class]]) {
        NSString *lower = verdict.lowercaseString;
        if ([lower containsString:@"ineffective"] || [lower containsString:@"no_effect"] || [lower containsString:@"not_effective"]) {
            return @"无效";
        }
        if ([lower containsString:@"effective"]) {
            return @"有效";
        }
        if ([lower containsString:@"error"] || [lower containsString:@"fail"]) {
            return @"失败";
        }
    }
    if ([item[@"current_stopped"] boolValue]) {
        return @"有效";
    }
    if (item[@"write_ret"] != nil && [item[@"write_ret"] integerValue] != 0) {
        return @"写入失败";
    }
    return @"未见效果";
}

#pragma mark - History chart (private view)

@interface CGHistoryChartView : UIView
@property (nonatomic, strong) NSArray<NSDictionary *> *samples;
@property (nonatomic, assign) BOOL longMode; // day/month: capacity + cycles only
@property (nonatomic, assign) BOOL showCurrent;
@property (nonatomic, assign) BOOL showVoltage;
- (void)updateWithSamples:(NSArray<NSDictionary *> *)samples longMode:(BOOL)longMode showCurrent:(BOOL)showCurrent showVoltage:(BOOL)showVoltage;
@end

@implementation CGHistoryChartView

- (void)updateWithSamples:(NSArray<NSDictionary *> *)samples longMode:(BOOL)longMode showCurrent:(BOOL)showCurrent showVoltage:(BOOL)showVoltage {
    self.samples = samples ?: @[];
    self.longMode = longMode;
    self.showCurrent = showCurrent;
    self.showVoltage = showVoltage;
    [self setNeedsDisplay];
}

static CGFloat CGChartValue(NSDictionary *sample, NSString *key, NSString *altKey) {
    id value = sample[key] ?: sample[altKey];
    if ([value respondsToSelector:@selector(doubleValue)]) {
        return (CGFloat)[value doubleValue];
    }
    return 0;
}

- (void)drawRect:(CGRect)rect {
    CGContextRef ctx = UIGraphicsGetCurrentContext();
    if (ctx == NULL) {
        return;
    }
    CGFloat padL = 34, padR = 10, padT = 10, padB = 26;
    CGRect plot = CGRectMake(padL, padT, rect.size.width - padL - padR, rect.size.height - padT - padB);
    if (self.samples.count == 0) {
        NSString *empty = @"暂无样本";
        NSDictionary *attrs = @{NSFontAttributeName: [UIFont systemFontOfSize:14 weight:UIFontWeightRegular], NSForegroundColorAttributeName: [UIColor secondaryLabelColor]};
        CGSize size = [empty sizeWithAttributes:attrs];
        [empty drawInRect:CGRectMake((rect.size.width - size.width) / 2.0, (rect.size.height - size.height) / 2.0, size.width, size.height) withAttributes:attrs];
        return;
    }
    // Grid: 4 horizontal lines with 0% / 50% / 100% labels for capacity.
    [[UIColor separatorColor] setStroke];
    CGContextSetLineWidth(ctx, 0.5);
    for (NSInteger i = 0; i <= 4; i++) {
        CGFloat y = plot.origin.y + plot.size.height * (CGFloat)i / 4.0;
        CGContextMoveToPoint(ctx, plot.origin.x, y);
        CGContextAddLineToPoint(ctx, plot.origin.x + plot.size.width, y);
        CGContextStrokePath(ctx);
        NSString *label = [NSString stringWithFormat:@"%ld%%", (long)(100 - i * 25)];
        NSDictionary *attrs = @{NSFontAttributeName: [UIFont systemFontOfSize:10], NSForegroundColorAttributeName: [UIColor secondaryLabelColor]};
        [label drawInRect:CGRectMake(0, y - 6, padL - 4, 12) withAttributes:attrs];
    }
    NSUInteger count = self.samples.count;
    CGFloat stepX = count > 1 ? plot.size.width / (CGFloat)(count - 1) : 0;
    // Capacity (0–100, fixed scale) + fill.
    UIBezierPath *capPath = [UIBezierPath bezierPath];
    UIBezierPath *capFill = [UIBezierPath bezierPath];
    for (NSUInteger i = 0; i < count; i++) {
        CGFloat cap = CGChartValue(self.samples[i], @"CurrentCapacity", @"capacity");
        cap = MAX(0, MIN(100, cap));
        CGFloat x = plot.origin.x + stepX * (CGFloat)i;
        CGFloat y = plot.origin.y + plot.size.height * (1.0 - cap / 100.0);
        if (i == 0) {
            [capPath moveToPoint:CGPointMake(x, y)];
            [capFill moveToPoint:CGPointMake(x, plot.origin.y + plot.size.height)];
            [capFill addLineToPoint:CGPointMake(x, y)];
        } else {
            [capPath addLineToPoint:CGPointMake(x, y)];
            [capFill addLineToPoint:CGPointMake(x, y)];
        }
    }
    [capFill addLineToPoint:CGPointMake(plot.origin.x + stepX * (CGFloat)(count - 1), plot.origin.y + plot.size.height)];
    [capFill closePath];
    [[[UIColor systemBlueColor] colorWithAlphaComponent:0.15] setFill];
    [capFill fill];
    [[UIColor systemBlueColor] setStroke];
    capPath.lineWidth = 2.0;
    [capPath stroke];
    // Temperature (normalised per-series, orange).
    CGFloat tMin = CGFLOAT_MAX, tMax = -CGFLOAT_MAX;
    for (NSDictionary *sample in self.samples) {
        CGFloat t = CGChartValue(sample, @"Temperature", @"temperature");
        if (t > 200) { t /= 100.0; }
        tMin = MIN(tMin, t); tMax = MAX(tMax, t);
    }
    if (tMax > tMin) {
        UIBezierPath *tempPath = [UIBezierPath bezierPath];
        for (NSUInteger i = 0; i < count; i++) {
            CGFloat t = CGChartValue(self.samples[i], @"Temperature", @"temperature");
            if (t > 200) { t /= 100.0; }
            CGFloat x = plot.origin.x + stepX * (CGFloat)i;
            CGFloat y = plot.origin.y + plot.size.height * (1.0 - (t - tMin) / (tMax - tMin));
            if (i == 0) { [tempPath moveToPoint:CGPointMake(x, y)]; } else { [tempPath addLineToPoint:CGPointMake(x, y)]; }
        }
        [[UIColor systemOrangeColor] setStroke];
        tempPath.lineWidth = 1.5;
        [tempPath stroke];
    }
    if (!self.longMode) {
        // Current (green, normalised per-series, signed) and voltage
        // (purple, normalised per-series) overlays, only on user toggle.
        if (self.showCurrent) {
            CGFloat aMin = CGFLOAT_MAX, aMax = -CGFLOAT_MAX;
            for (NSDictionary *sample in self.samples) {
                CGFloat a = CGChartValue(sample, @"InstantAmperage", @"Amperage");
                aMin = MIN(aMin, a); aMax = MAX(aMax, a);
            }
            if (aMax > aMin) {
                UIBezierPath *ampPath = [UIBezierPath bezierPath];
                for (NSUInteger i = 0; i < count; i++) {
                    CGFloat a = CGChartValue(self.samples[i], @"InstantAmperage", @"Amperage");
                    CGFloat x = plot.origin.x + stepX * (CGFloat)i;
                    CGFloat y = plot.origin.y + plot.size.height * (1.0 - (a - aMin) / (aMax - aMin));
                    if (i == 0) { [ampPath moveToPoint:CGPointMake(x, y)]; } else { [ampPath addLineToPoint:CGPointMake(x, y)]; }
                }
                [[UIColor systemGreenColor] setStroke];
                ampPath.lineWidth = 1.5;
                [ampPath stroke];
            }
        }
        if (self.showVoltage) {
            CGFloat vMin = CGFLOAT_MAX, vMax = -CGFLOAT_MAX;
            for (NSDictionary *sample in self.samples) {
                CGFloat v = CGChartValue(sample, @"Voltage", @"IncomingVoltage");
                if (v > 100) { v /= 1000.0; }
                vMin = MIN(vMin, v); vMax = MAX(vMax, v);
            }
            if (vMax > vMin) {
                UIBezierPath *voltPath = [UIBezierPath bezierPath];
                for (NSUInteger i = 0; i < count; i++) {
                    CGFloat v = CGChartValue(self.samples[i], @"Voltage", @"IncomingVoltage");
                    if (v > 100) { v /= 1000.0; }
                    CGFloat x = plot.origin.x + stepX * (CGFloat)i;
                    CGFloat y = plot.origin.y + plot.size.height * (1.0 - (v - vMin) / (vMax - vMin));
                    if (i == 0) { [voltPath moveToPoint:CGPointMake(x, y)]; } else { [voltPath addLineToPoint:CGPointMake(x, y)]; }
                }
                [[UIColor systemPurpleColor] setStroke];
                voltPath.lineWidth = 1.5;
                [voltPath stroke];
            }
        }
    } else {
        // Day/month: cycles (teal, normalised per-series).
        CGFloat cMin = CGFLOAT_MAX, cMax = -CGFLOAT_MAX;
        for (NSDictionary *sample in self.samples) {
            CGFloat c = CGChartValue(sample, @"CycleCount", @"cycles");
            cMin = MIN(cMin, c); cMax = MAX(cMax, c);
        }
        if (cMax > cMin) {
            UIBezierPath *cyclePath = [UIBezierPath bezierPath];
            for (NSUInteger i = 0; i < count; i++) {
                CGFloat c = CGChartValue(self.samples[i], @"CycleCount", @"cycles");
                CGFloat x = plot.origin.x + stepX * (CGFloat)i;
                CGFloat y = plot.origin.y + plot.size.height * (1.0 - (c - cMin) / (cMax - cMin));
                if (i == 0) { [cyclePath moveToPoint:CGPointMake(x, y)]; } else { [cyclePath addLineToPoint:CGPointMake(x, y)]; }
            }
            [[UIColor systemTealColor] setStroke];
            cyclePath.lineWidth = 1.5;
            [cyclePath stroke];
        }
    }
}

@end

#pragma mark - History analytics

@implementation CGHistoryAnalyticsViewController {
    CGCapsuleFilterView *_filter;
    CGCapsuleFilterView *_eventFilter;
    CGHistoryChartView *_chartView;
    UILabel *_summaryLabel;
    UILabel *_pageLabel;
    UILabel *_hintLabel;
    UIStackView *_timelineStack;
    UISwitch *_statsSwitch;
    UIButton *_ampButton;
    UIButton *_voltButton;
    NSArray<NSDictionary *> *_min5Samples;
    NSArray<NSDictionary *> *_hourSamples;
    NSArray<NSDictionary *> *_daySamples;
    NSArray<NSDictionary *> *_monthSamples;
    NSArray<NSDictionary *> *_policyEvents;
    NSInteger _offset;
    BOOL _showCurrent;
    BOOL _showVoltage;
    NSInteger _eventFilterIndex;
    BOOL _statsEnabled;
    double _tempLimit;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor systemGroupedBackgroundColor];
    self.title = @"历史统计";
    UIStackView *stack = CGVerticalStack(@[]);
    __weak typeof(self) weakSelf = self;
    _filter = [[CGCapsuleFilterView alloc] initWithTitles:@[@"5分钟", @"小时", @"天", @"月"]
                                            selectedIndex:0
                                              changeHandler:^(NSInteger index) {
        weakSelf->_offset = 0;
        [weakSelf refreshHistory];
    }];
    _eventFilter = [[CGCapsuleFilterView alloc] initWithTitles:@[@"全部", @"状态", @"保持", @"接管", @"温控"]
                                                 selectedIndex:0
                                                   changeHandler:^(NSInteger index) {
        weakSelf->_eventFilterIndex = index;
        [weakSelf refreshTimeline];
    }];
    _chartView = [[CGHistoryChartView alloc] init];
    _chartView.backgroundColor = [UIColor clearColor];
    [_chartView.heightAnchor constraintEqualToConstant:220].active = YES;
    _summaryLabel = CGCardLabel(@"正在读取历史数据…", 15, UIFontWeightRegular, [UIColor labelColor]);
    _hintLabel = CGCardLabel(@"默认显示电量与温度；5 分钟/小时档可再叠加电流、电压。", 13, UIFontWeightRegular, [UIColor secondaryLabelColor]);
    _pageLabel = CGCardLabel(@"", 13, UIFontWeightSemibold, [UIColor secondaryLabelColor]);
    _pageLabel.textAlignment = NSTextAlignmentCenter;
    _timelineStack = CGVerticalStack(@[]);
    _statsSwitch = [[UISwitch alloc] init];
    [_statsSwitch addTarget:self action:@selector(statsSwitchChanged:) forControlEvents:UIControlEventValueChanged];
    _statsSwitch.enabled = NO;
    _ampButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [_ampButton setTitle:@"电流" forState:UIControlStateNormal];
    _ampButton.titleLabel.font = [UIFont systemFontOfSize:14 weight:UIFontWeightSemibold];
    [_ampButton addTarget:self action:@selector(ampTapped) forControlEvents:UIControlEventTouchUpInside];
    _voltButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [_voltButton setTitle:@"电压" forState:UIControlStateNormal];
    _voltButton.titleLabel.font = [UIFont systemFontOfSize:14 weight:UIFontWeightSemibold];
    [_voltButton addTarget:self action:@selector(voltTapped) forControlEvents:UIControlEventTouchUpInside];
    [self updateToggleButtons];
    UIStackView *statsRow = [[UIStackView alloc] initWithArrangedSubviews:@[CGCardLabel(@"历史统计采集", 16, UIFontWeightSemibold, [UIColor labelColor]), _statsSwitch]];
    statsRow.axis = UILayoutConstraintAxisHorizontal;
    statsRow.spacing = 12;
    statsRow.alignment = UIStackViewAlignmentCenter;
    UIStackView *toggleRow = [[UIStackView alloc] initWithArrangedSubviews:@[_ampButton, _voltButton]];
    toggleRow.axis = UILayoutConstraintAxisHorizontal;
    toggleRow.spacing = 12;
    UIStackView *pageRow = [[UIStackView alloc] initWithArrangedSubviews:@[CGTextButton(@"‹ 上一页", self, @selector(prevPage)), _pageLabel, CGTextButton(@"下一页 ›", self, @selector(nextPage))]];
    pageRow.axis = UILayoutConstraintAxisHorizontal;
    pageRow.spacing = 8;
    pageRow.distribution = UIStackViewDistributionFillEqually;
    [stack addArrangedSubview:CGBackButton(self, @selector(cgGoBack))];
    [stack addArrangedSubview:CGCardLabel(@"历史统计", 24, UIFontWeightBold, [UIColor labelColor])];
    [stack addArrangedSubview:_filter];
    [stack addArrangedSubview:CGCardWithStack(CGVerticalStack(@[statsRow, CGCardLabel(@"关掉后不再采集新记录；已有记录可以保留，也可以一起删掉。", 13, UIFontWeightRegular, [UIColor secondaryLabelColor])]))];
    [stack addArrangedSubview:CGCardWithStack(CGVerticalStack(@[_chartView, _hintLabel, pageRow]))];
    [stack addArrangedSubview:toggleRow];
    [stack addArrangedSubview:CGCardWithStack(CGVerticalStack(@[_summaryLabel]))];
    [stack addArrangedSubview:CGCardLabel(@"最近策略事件", 16, UIFontWeightSemibold, [UIColor labelColor])];
    [stack addArrangedSubview:_eventFilter];
    [stack addArrangedSubview:CGCardWithStack(_timelineStack)];
    [stack addArrangedSubview:CGTextButton(@"刷新", self, @selector(refreshHistory))];
    CGAddScrollStack(self, stack);
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self refreshHistory];
}

- (void)cgGoBack {
    [self.navigationController popViewControllerAnimated:YES];
}

- (void)updateToggleButtons {
    BOOL longMode = _filter.selectedIndex >= 2;
    _ampButton.enabled = !longMode;
    _voltButton.enabled = !longMode;
    _ampButton.alpha = longMode ? 0.4 : 1.0;
    _voltButton.alpha = longMode ? 0.4 : 1.0;
    _ampButton.backgroundColor = _showCurrent ? [UIColor systemBlueColor] : [UIColor tertiarySystemFillColor];
    [_ampButton setTitleColor:_showCurrent ? [UIColor whiteColor] : [UIColor labelColor] forState:UIControlStateNormal];
    _voltButton.backgroundColor = _showVoltage ? [UIColor systemBlueColor] : [UIColor tertiarySystemFillColor];
    [_voltButton setTitleColor:_showVoltage ? [UIColor whiteColor] : [UIColor labelColor] forState:UIControlStateNormal];
    _hintLabel.text = longMode ? @"天/月档只显示电量与循环次数。" : @"默认显示电量与温度；点下面可再叠加电流、电压。";
}

- (void)ampTapped {
    _showCurrent = !_showCurrent;
    [self updateToggleButtons];
    [self updateChartAndSummary];
}

- (void)voltTapped {
    _showVoltage = !_showVoltage;
    [self updateToggleButtons];
    [self updateChartAndSummary];
}

- (void)prevPage {
    if (_offset >= 60) {
        _offset -= 60;
        [self updateChartAndSummary];
    }
}

- (void)nextPage {
    NSArray *all = [self samplesForSegment:_filter.selectedIndex];
    if (_offset + 60 < (NSInteger)all.count) {
        _offset += 60;
        [self updateChartAndSummary];
    }
}

- (NSArray<NSDictionary *> *)samplesForSegment:(NSInteger)index {
    if (index == 1) return _hourSamples ?: @[];
    if (index == 2) return _daySamples ?: @[];
    if (index == 3) return _monthSamples ?: @[];
    return _min5Samples ?: @[];
}

- (NSArray<NSDictionary *> *)visibleSamples {
    NSArray *all = [self samplesForSegment:_filter.selectedIndex];
    if (_offset < 0) { _offset = 0; }
    if (_offset >= (NSInteger)all.count) { _offset = MAX(0, (NSInteger)all.count - 60); }
    NSInteger end = MIN(_offset + 60, (NSInteger)all.count);
    if (end <= _offset) { return @[]; }
    return [all subarrayWithRange:NSMakeRange((NSUInteger)_offset, (NSUInteger)(end - _offset))];
}

- (void)refreshHistory {
    __weak typeof(self) weakSelf = self;
    _statsEnabled = [CLBatteryManager shared].historyStatsEnabled;
    _statsSwitch.on = _statsEnabled;
    _statsSwitch.enabled = YES;
    [[CGDaemonClient shared] fetchConfigWithCompletion:^(CGConfig *config, NSError *configError) {
        (void)configError;
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (strongSelf == nil) { return; }
        double tempLimit = config ? (double)config.tempAbove : 40.0;
        [[CGDaemonClient shared] fetchStatisticsWithCompletion:^(NSDictionary *response, NSError *error) {
            __strong typeof(weakSelf) strongSelf2 = weakSelf;
            if (strongSelf2 == nil) { return; }
            if (error != nil || response == nil) {
                strongSelf2->_summaryLabel.text = @"历史数据读取失败（守护进程可能离线）。";
                [strongSelf2->_chartView updateWithSamples:@[] longMode:NO showCurrent:NO showVoltage:NO];
                return;
            }
            NSDictionary *data = response[@"data"];
            if (![data isKindOfClass:[NSDictionary class]]) { data = response; }
            strongSelf2->_min5Samples = [data[@"min5"] isKindOfClass:[NSArray class]] ? data[@"min5"] : @[];
            strongSelf2->_hourSamples = [data[@"hour"] isKindOfClass:[NSArray class]] ? data[@"hour"] : @[];
            strongSelf2->_daySamples = [data[@"day"] isKindOfClass:[NSArray class]] ? data[@"day"] : @[];
            strongSelf2->_monthSamples = [data[@"month"] isKindOfClass:[NSArray class]] ? data[@"month"] : @[];
            strongSelf2->_tempLimit = tempLimit;
            [strongSelf2 updateChartAndSummary];
        }];
    }];
    [[CGDaemonClient shared] fetchPolicyEventsWithLimit:100 completion:^(NSDictionary *response, NSError *error) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (strongSelf == nil || error != nil) { return; }
        NSArray *events = response[@"data"];
        if (![events isKindOfClass:[NSArray class]]) { events = response[@"events"]; }
        if ([events isKindOfClass:[NSArray class]]) {
            strongSelf->_policyEvents = events;
            [strongSelf refreshTimeline];
        }
    }];
}

- (void)updateChartAndSummary {
    [self updateToggleButtons];
    NSArray *all = [self samplesForSegment:_filter.selectedIndex];
    NSArray *visible = [self visibleSamples];
    BOOL longMode = _filter.selectedIndex >= 2;
    [_chartView updateWithSamples:visible longMode:longMode showCurrent:(longMode ? NO : _showCurrent) showVoltage:(longMode ? NO : _showVoltage)];
    NSInteger total = (NSInteger)all.count;
    NSInteger start = total == 0 ? 0 : _offset + 1;
    NSInteger end = _offset + (NSInteger)visible.count;
    _pageLabel.text = total == 0 ? @"暂无记录" : [NSString stringWithFormat:@"第 %ld–%ld 条，共 %ld 条", (long)start, (long)end, (long)total];
    NSArray *bucketMinutes = @[@5, @60, @1440, @43200];
    NSArray *bucketTitles = @[@"5分钟", @"小时", @"天", @"月"];
    NSInteger index = _filter.selectedIndex;
    if (index < 0 || index >= 4) { index = 0; }
    NSInteger minutes = [bucketMinutes[(NSUInteger)index] integerValue];
    double rate = [CGHistoryAnalytics averageChargeRatePercentPerHourFromSamples:visible bucketMinutes:minutes];
    NSInteger span = [CGHistoryAnalytics longestChargingSpanMinutesFromSamples:visible bucketMinutes:minutes];
    NSDictionary *temp = [CGHistoryAnalytics temperatureSummaryFromSamples:visible highTempLimit:_tempLimit];
    NSMutableString *summary = [NSMutableString string];
    [summary appendFormat:@"范围：%@，当前页 %ld 条。", bucketTitles[(NSUInteger)index], (long)visible.count];
    if (rate > 0) {
        [summary appendFormat:@"充电速度约 %.0f%%/小时；最长连续充电 %ld 分钟。", rate, (long)span];
    } else {
        [summary appendString:@"暂无可用的充电速度样本（需要先开启历史统计并充电一段时间）。"];
    }
    [summary appendFormat:@"\n本页最高温度 %.1f℃，≥%.0f℃ 的样本 %ld 条（共 %ld 条）。",
     [temp[@"maxTemperature"] doubleValue], _tempLimit, (long)[temp[@"samplesOverLimit"] integerValue], (long)[temp[@"sampleCount"] integerValue]];
    if (!_statsEnabled) {
        [summary appendString:@"\n统计采集目前是关的，上面只展示已有记录。"];
    }
    _summaryLabel.text = [summary copy];
}

- (void)statsSwitchChanged:(UISwitch *)sender {
    if (sender.on) {
        [CLBatteryManager shared].historyStatsEnabled = YES;
        _statsEnabled = YES;
        [self refreshHistory];
        return;
    }
    __weak typeof(self) weakSelf = self;
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"关闭历史统计" message:@"关闭后将停止继续采集历史统计。你可以保留已有记录，或同时删除已有历史统计数据。" preferredStyle:UIAlertControllerStyleActionSheet];
    [alert addAction:[UIAlertAction actionWithTitle:@"保留历史记录" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        [CLBatteryManager shared].historyStatsEnabled = NO;
        weakSelf->_statsEnabled = NO;
        [weakSelf refreshHistory];
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"删除历史记录" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action) {
        [CLBatteryManager shared].historyStatsEnabled = NO;
        weakSelf->_statsEnabled = NO;
        [[CLBatteryManager shared] clearStatisticsWithCompletion:^(BOOL success) {
            dispatch_async(dispatch_get_main_queue(), ^{
                if (success) {
                    weakSelf->_min5Samples = @[]; weakSelf->_hourSamples = @[]; weakSelf->_daySamples = @[]; weakSelf->_monthSamples = @[];
                }
                [weakSelf refreshHistory];
            });
        }];
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:^(UIAlertAction *action) {
        weakSelf->_statsSwitch.on = YES;
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (BOOL)eventMatchesFilter:(NSDictionary *)event {
    if (_eventFilterIndex == 0) { return YES; }
    NSString *text = [NSString stringWithFormat:@"%@ %@ %@ %@", event[@"type"] ?: @"", event[@"to"] ?: @"", event[@"state"] ?: @"", event[@"reason"] ?: @""];
    NSString *lower = text.lowercaseString;
    if (_eventFilterIndex == 1) {
        return ![lower containsString:@"hold"] && ![lower containsString:@"smart"] && ![lower containsString:@"thermal"] && ![lower containsString:@"temperature"];
    }
    if (_eventFilterIndex == 2) { return [lower containsString:@"hold"]; }
    if (_eventFilterIndex == 3) { return [lower containsString:@"smart"]; }
    if (_eventFilterIndex == 4) { return [lower containsString:@"thermal"] || [lower containsString:@"temperature"]; }
    return YES;
}

- (void)refreshTimeline {
    for (UIView *view in _timelineStack.arrangedSubviews) {
        [_timelineStack removeArrangedSubview:view];
        [view removeFromSuperview];
    }
    NSArray *events = _policyEvents ?: @[];
    NSInteger shown = 0;
    for (NSDictionary *event in events) {
        if (![event isKindOfClass:[NSDictionary class]]) { continue; }
        if (![self eventMatchesFilter:event]) { continue; }
        if (shown >= 20) { break; }
        shown += 1;
        NSString *state = CGPolicyEventText(event);
        UIColor *dotColor = [UIColor systemGrayColor];
        if ([state containsString:@"停充"]) { dotColor = [UIColor systemGreenColor]; }
        else if ([state containsString:@"恢复"]) { dotColor = [UIColor systemOrangeColor]; }
        UIView *dot = [[UIView alloc] init];
        dot.backgroundColor = dotColor;
        dot.layer.cornerRadius = 6;
        [dot.widthAnchor constraintEqualToConstant:12].active = YES;
        [dot.heightAnchor constraintEqualToConstant:12].active = YES;
        NSMutableArray<NSString *> *parts = [NSMutableArray arrayWithObject:state];
        NSTimeInterval ts = [event[@"ts"] doubleValue];
        if (ts > 0) {
            NSDateFormatter *fmt = [[NSDateFormatter alloc] init];
            fmt.dateFormat = @"MM-dd HH:mm";
            [parts addObject:[fmt stringFromDate:[NSDate dateWithTimeIntervalSince1970:ts]]];
        }
        NSInteger cap = [event[@"capacity"] integerValue];
        if (cap > 0) { [parts addObject:[NSString stringWithFormat:@"%ld%%", (long)cap]]; }
        NSInteger cur = [event[@"current"] integerValue];
        if (cur != 0) { [parts addObject:[NSString stringWithFormat:@"%ld mA", (long)cur]]; }
        NSInteger tempRaw = [event[@"temperature"] integerValue];
        if (tempRaw > 0) { [parts addObject:[NSString stringWithFormat:@"%.1f℃", tempRaw > 200 ? tempRaw / 100.0 : (double)tempRaw]]; }
        UILabel *label = CGCardLabel([parts componentsJoinedByString:@" · "], 15, UIFontWeightRegular, [UIColor labelColor]);
        UIStackView *row = [[UIStackView alloc] initWithArrangedSubviews:@[dot, label]];
        row.axis = UILayoutConstraintAxisHorizontal;
        row.spacing = 10;
        row.alignment = UIStackViewAlignmentCenter;
        [_timelineStack addArrangedSubview:row];
    }
    if (shown == 0) {
        [_timelineStack addArrangedSubview:CGCardLabel(@"暂无策略事件。", 15, UIFontWeightRegular, [UIColor secondaryLabelColor])];
    }
}

@end

#pragma mark - Compat result (real engine, in-page)

@implementation CGCompatResultViewController {
    CLBatteryCompatibilityEngine *_engine;
    UISwitch *_stopSwitch;
    UISwitch *_smartSwitch;
    UISwitch *_inflowSwitch;
    UILabel *_daemonRow;
    UILabel *_pluggedRow;
    UILabel *_batteryRow;
    UILabel *_currentTestLabel;
    UILabel *_liveCurrentLabel;
    UILabel *_elapsedLabel;
    UIProgressView *_progressView;
    UILabel *_overallLabel;
    UILabel *_overallNoteLabel;
    UIButton *_startButton;
    UIButton *_probeButton;
    UILabel *_probeResultLabel;
    UIStackView *_probeStack;
    NSMutableArray<NSNumber *> *_verdicts;
    NSMutableArray<NSDictionary *> *_resultLabels; // per kind: @{verdict, detail1, detail2, note}
    BOOL _engineRunning;
    BOOL _probeRunning;
    BOOL _starting;
    BOOL _snapshotPrompted;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor systemGroupedBackgroundColor];
    self.title = @"电池兼容性测试";
    _engine = [[CLBatteryCompatibilityEngine alloc] init];
    _verdicts = [NSMutableArray arrayWithArray:@[@0, @0, @0]];
    _resultLabels = [NSMutableArray array];
    UIStackView *stack = CGVerticalStack(@[]);
    _stopSwitch = [[UISwitch alloc] init]; _stopSwitch.on = YES;
    _smartSwitch = [[UISwitch alloc] init]; _smartSwitch.on = YES;
    _inflowSwitch = [[UISwitch alloc] init]; _inflowSwitch.on = YES;
    _daemonRow = CGCardLabel(@"守护进程在线：—", 15, UIFontWeightRegular, [UIColor labelColor]);
    _pluggedRow = CGCardLabel(@"已插电：—", 15, UIFontWeightRegular, [UIColor labelColor]);
    _batteryRow = CGCardLabel(@"电量在 10%–95% 之间：—", 15, UIFontWeightRegular, [UIColor labelColor]);
    _currentTestLabel = CGCardLabel(@"还没开始", 16, UIFontWeightSemibold, [UIColor labelColor]);
    _liveCurrentLabel = CGCardLabel(@"实时电流：—", 15, UIFontWeightRegular, [UIColor labelColor]);
    _elapsedLabel = CGCardLabel(@"已用时间：0 秒", 15, UIFontWeightRegular, [UIColor labelColor]);
    _progressView = [[UIProgressView alloc] initWithProgressViewStyle:UIProgressViewStyleDefault];
    _overallLabel = CGCardLabel(@"还没开始测试，点开始后这里出结果", 17, UIFontWeightBold, [UIColor secondaryLabelColor]);
    _overallNoteLabel = CGCardLabel(@"", 14, UIFontWeightRegular, [UIColor systemOrangeColor]);
    _overallNoteLabel.hidden = YES;
    _startButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [_startButton setTitle:@"开始测试" forState:UIControlStateNormal];
    _startButton.titleLabel.font = [UIFont systemFontOfSize:17 weight:UIFontWeightSemibold];
    [_startButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    _startButton.backgroundColor = [UIColor systemIndigoColor];
    _startButton.layer.cornerRadius = 16;
    [_startButton.heightAnchor constraintEqualToConstant:48].active = YES;
    [_startButton addTarget:self action:@selector(startTapped) forControlEvents:UIControlEventTouchUpInside];
    _probeButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [_probeButton setTitle:@"运行停充控制探针" forState:UIControlStateNormal];
    _probeButton.titleLabel.font = [UIFont systemFontOfSize:16 weight:UIFontWeightSemibold];
    [_probeButton addTarget:self action:@selector(probeTapped) forControlEvents:UIControlEventTouchUpInside];
    _probeResultLabel = CGCardLabel(@"还没跑过探针。探针会尝试多种停充写法并自动恢复，整轮约 1–2 分钟，请插着充电器运行。", 14, UIFontWeightRegular, [UIColor secondaryLabelColor]);
    _probeStack = CGVerticalStack(@[]);
    NSArray *kindTitles = @[@"停充测试", @"智能停充测试", @"禁流测试"];
    NSArray *kindNotes = @[@"传统停充路径是否真正停得住电流", @"预测式停充路径是否真正停得住电流", @"禁流后充电状态能否退出并恢复"];
    NSMutableArray<UIView *> *resultCards = [NSMutableArray array];
    for (NSInteger kind = 0; kind < 3; kind++) {
        UILabel *verdictLabel = CGCardLabel(@"未测试", 16, UIFontWeightSemibold, [UIColor secondaryLabelColor]);
        UILabel *detail1 = CGCardLabel(@"—", 14, UIFontWeightRegular, [UIColor secondaryLabelColor]);
        UILabel *detail2 = CGCardLabel(@"—", 14, UIFontWeightRegular, [UIColor secondaryLabelColor]);
        UILabel *note = CGCardLabel(kindNotes[(NSUInteger)kind], 13, UIFontWeightRegular, [UIColor secondaryLabelColor]);
        [_resultLabels addObject:@{@"verdict": verdictLabel, @"detail1": detail1, @"detail2": detail2, @"note": note}];
        [resultCards addObject:CGCardWithStack(CGVerticalStack(@[
            CGCardLabel(kindTitles[(NSUInteger)kind], 17, UIFontWeightBold, [UIColor labelColor]),
            verdictLabel, detail1, detail2, note]))];
    }
    [stack addArrangedSubview:CGBackButton(self, @selector(cgGoBack))];
    [stack addArrangedSubview:CGCardLabel(@"电池兼容性测试", 24, UIFontWeightBold, [UIColor labelColor])];
    [stack addArrangedSubview:CGCardWithStack(CGVerticalStack(@[
        CGCardLabel(@"一次测清本机支不支持停充与禁流。测试会短暂停充或禁流（每项最长约 2 分钟），结束后自动恢复原来的配置。测试期间请勿拔掉充电线。", 14, UIFontWeightRegular, [UIColor labelColor])]))];
    [stack addArrangedSubview:CGCardWithStack(CGVerticalStack(@[_daemonRow, _pluggedRow, _batteryRow]))];
    [stack addArrangedSubview:CGCardWithStack(CGVerticalStack(@[
        [self switchRowForCompat:@"停充测试" subtitle:@"传统停充路径" sw:_stopSwitch],
        [self switchRowForCompat:@"智能停充测试" subtitle:@"预测式停充路径" sw:_smartSwitch],
        [self switchRowForCompat:@"禁流测试" subtitle:@"禁流后退出与恢复" sw:_inflowSwitch]]))];
    [stack addArrangedSubview:_startButton];
    [stack addArrangedSubview:CGCardWithStack(CGVerticalStack(@[_currentTestLabel, _liveCurrentLabel, _elapsedLabel, _progressView]))];
    for (UIView *card in resultCards) { [stack addArrangedSubview:card]; }
    [stack addArrangedSubview:CGCardWithStack(CGVerticalStack(@[_overallLabel, _overallNoteLabel]))];
    [stack addArrangedSubview:CGCardWithStack(CGVerticalStack(@[_probeButton, _probeResultLabel, _probeStack]))];
    CGAddScrollStack(self, stack);
}

- (UIView *)switchRowForCompat:(NSString *)title subtitle:(NSString *)subtitle sw:(UISwitch *)sw {
    return CGSwitchRow(title, subtitle, sw);
}

- (void)cgGoBack {
    [self.navigationController popViewControllerAnimated:YES];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    if (!_snapshotPrompted && [CLBatteryCompatibilityEngine hasPendingSnapshot]) {
        _snapshotPrompted = YES;
        __weak typeof(self) weakSelf = self;
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"检测到未完成的测试" message:@"上次测试未正常结束，是否恢复测试前的配置？" preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"恢复" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
            [CLBatteryCompatibilityEngine restoreSnapshot:YES completion:^(BOOL ok) {
                CGShowAlert(weakSelf, nil, ok ? @"配置已恢复" : @"恢复失败，请检查守护进程状态");
            }];
        }]];
        [alert addAction:[UIAlertAction actionWithTitle:@"丢弃" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action) {
            [CLBatteryCompatibilityEngine clearSnapshot];
        }]];
        [self presentViewController:alert animated:YES completion:nil];
    }
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    if (_engineRunning) {
        [_engine cancel];
    }
}

- (void)updateControls {
    _startButton.enabled = !_probeRunning;
    _startButton.alpha = _startButton.enabled ? 1.0 : 0.4;
    [_startButton setTitle:_engineRunning ? @"取消测试" : @"开始测试" forState:UIControlStateNormal];
    _startButton.backgroundColor = _engineRunning ? [UIColor systemRedColor] : [UIColor systemIndigoColor];
    _stopSwitch.enabled = !_engineRunning;
    _smartSwitch.enabled = !_engineRunning;
    _inflowSwitch.enabled = !_engineRunning;
    _probeButton.enabled = !_engineRunning && !_probeRunning;
    _probeButton.alpha = _probeButton.enabled ? 1.0 : 0.4;
}

- (void)startTapped {
    if (_engineRunning) {
        [_engine cancel];
        return;
    }
    if (_probeRunning || _starting) { return; }
    if (!_stopSwitch.on && !_smartSwitch.on && !_inflowSwitch.on) {
        CGShowAlert(self, nil, @"请至少选择一项测试");
        return;
    }
    _starting = YES;
    _startButton.enabled = NO;
    _startButton.alpha = 0.4;
    __weak typeof(self) weakSelf = self;
    [CLBatteryCompatibilityEngine runPrecheckWithCompletion:^(NSDictionary<NSString *, NSNumber *> *results) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (strongSelf == nil) { return; }
        strongSelf->_daemonRow.text = [results[@"daemon"] boolValue] ? @"守护进程在线：✓" : @"守护进程在线：未运行";
        strongSelf->_pluggedRow.text = [results[@"plugged"] boolValue] ? @"已插电：✓" : @"已插电：请插电后重试";
        strongSelf->_batteryRow.text = [results[@"battery"] boolValue] ? @"电量在 10%–95% 之间：✓" : @"电量在 10%–95% 之间：电量不在范围内";
        BOOL allOK = [results[@"daemon"] boolValue] && [results[@"plugged"] boolValue] && [results[@"battery"] boolValue];
        if (!allOK) {
            strongSelf->_starting = NO;
            [strongSelf updateControls];
            return;
        }
        [CLBatteryCompatibilityEngine writeSnapshotWithCompletion:^(BOOL ok) {
            __strong typeof(weakSelf) strongSelf2 = weakSelf;
            if (strongSelf2 == nil) { return; }
            strongSelf2->_starting = NO;
            if (!ok) {
                CGShowAlert(strongSelf2, @"无法读取当前配置", @"守护进程未响应，请重试。");
                [strongSelf2 updateControls];
                return;
            }
            [strongSelf2 beginTestFlow];
        }];
    }];
}

- (void)beginTestFlow {
    for (NSInteger i = 0; i < 3; i++) { _verdicts[(NSUInteger)i] = @0; }
    for (NSDictionary *rows in _resultLabels) {
        ((UILabel *)rows[@"verdict"]).text = @"未测试";
        ((UILabel *)rows[@"verdict"]).textColor = [UIColor secondaryLabelColor];
        ((UILabel *)rows[@"detail1"]).text = @"—";
        ((UILabel *)rows[@"detail2"]).text = @"—";
    }
    _overallLabel.text = @"测试进行中…";
    _overallLabel.textColor = [UIColor labelColor];
    _overallNoteLabel.hidden = YES;
    _currentTestLabel.text = @"准备开始";
    _liveCurrentLabel.text = @"实时电流：—";
    _elapsedLabel.text = @"已用时间：0 秒";
    _progressView.progress = 0;
    NSArray *selection = @[@(_stopSwitch.on), @(_smartSwitch.on), @(_inflowSwitch.on)];
    __weak typeof(self) weakSelf = self;
    _engine.onEvent = ^(CLCompatTestEvent *event) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [weakSelf handleEngineEvent:event];
        });
    };
    _engineRunning = YES;
    [self updateControls];
    [_engine startWithSelection:selection];
}

- (void)handleEngineEvent:(CLCompatTestEvent *)event {
    switch (event.kind) {
        case CGCompatEventKindPhase:
            _currentTestLabel.text = event.message ?: @"—";
            _progressView.progress = 0;
            break;
        case CGCompatEventKindSample:
            _liveCurrentLabel.text = [NSString stringWithFormat:@"实时电流：%ld mA", (long)event.currentmA];
            _elapsedLabel.text = [NSString stringWithFormat:@"已用时间：%ld 秒", (long)event.elapsed];
            _progressView.progress = (float)event.progress;
            break;
        case CGCompatEventKindState:
            _currentTestLabel.text = event.testKind == CGCompatTestKindInflow
                ? [NSString stringWithFormat:@"检测到退出充电（%ld 秒）", (long)event.elapsed]
                : [NSString stringWithFormat:@"检测到状态变化（%ld 秒）", (long)event.elapsed];
            break;
        case CGCompatEventKindVerdict:
            [self applyVerdictEvent:event];
            _progressView.progress = 0;
            break;
        case CGCompatEventKindFinished:
            _currentTestLabel.text = @"测试完成";
            _progressView.progress = 1.0;
            [self updateOverall];
            if (event.message.length > 0) {
                _overallNoteLabel.text = event.message;
                _overallNoteLabel.hidden = NO;
            }
            _engineRunning = NO;
            [self updateControls];
            break;
        case CGCompatEventKindAborted:
            _currentTestLabel.text = @"已中止";
            if (event.message.length > 0) { _currentTestLabel.text = event.message; }
            _engineRunning = NO;
            [self updateControls];
            break;
    }
}

- (void)applyVerdictEvent:(CLCompatTestEvent *)event {
    NSInteger kind = (NSInteger)event.testKind;
    if (kind < 0 || kind > 2) { return; }
    _verdicts[(NSUInteger)kind] = @(event.verdict);
    NSDictionary *rows = _resultLabels[(NSUInteger)kind];
    UILabel *verdictLabel = rows[@"verdict"];
    UILabel *detail1 = rows[@"detail1"];
    UILabel *detail2 = rows[@"detail2"];
    switch (event.verdict) {
        case CGCompatTestVerdictSupported: verdictLabel.text = @"支持"; verdictLabel.textColor = [UIColor systemGreenColor]; break;
        case CGCompatTestVerdictUnsupported: verdictLabel.text = @"无法支持"; verdictLabel.textColor = [UIColor systemRedColor]; break;
        case CGCompatTestVerdictError: verdictLabel.text = @"异常"; verdictLabel.textColor = [UIColor systemOrangeColor]; break;
        default: verdictLabel.text = @"未测试"; verdictLabel.textColor = [UIColor secondaryLabelColor]; break;
    }
    if (event.testKind == CGCompatTestKindInflow) {
        detail1.text = event.exitElapsed >= 0 ? [NSString stringWithFormat:@"退出充电耗时 %ld 秒", (long)event.exitElapsed] : @"退出耗时：—";
        NSString *mode = @"—";
        if (event.restoreMode == CGCompatRestoreSystem) { mode = @"系统自愈"; }
        else if (event.restoreMode == CGCompatRestoreAfterRelease) { mode = @"释放后恢复"; }
        detail2.text = [NSString stringWithFormat:@"恢复方式：%@%@", mode, event.returnElapsed >= 0 ? [NSString stringWithFormat:@"，耗时 %ld 秒", (long)event.returnElapsed] : @""];
        ((UILabel *)rows[@"note"]).text = event.message.length > 0 ? event.message : @"禁流后退出与恢复";
    } else {
        detail1.text = event.maxCurrentmA == NSIntegerMin ? @"最高电流：—" : [NSString stringWithFormat:@"最高电流 %ld mA", (long)event.maxCurrentmA];
        detail2.text = event.minCurrentmA == NSIntegerMax ? @"最低电流：—" : [NSString stringWithFormat:@"最低电流 %ld mA，状态变化耗时 %ld 秒", (long)event.minCurrentmA, (long)event.elapsed];
    }
}

- (void)updateOverall {
    BOOL stopTested = [_verdicts[0] integerValue] != 0;
    BOOL smartTested = [_verdicts[1] integerValue] != 0;
    BOOL inflowTested = [_verdicts[2] integerValue] != 0;
    if (!stopTested && !smartTested && !inflowTested) {
        _overallLabel.text = @"还没开始测试，点开始后这里出结果";
        _overallLabel.textColor = [UIColor secondaryLabelColor];
        return;
    }
    BOOL stopOK = [_verdicts[0] integerValue] == 1 || [_verdicts[1] integerValue] == 1;
    BOOL inflowOK = [_verdicts[2] integerValue] == 1;
    BOOL smartOnly = [_verdicts[1] integerValue] == 1 && [_verdicts[0] integerValue] == 2;
    BOOL stopUnsupported = [_verdicts[0] integerValue] == 2 || [_verdicts[1] integerValue] == 2;
    BOOL inflowUnsupported = [_verdicts[2] integerValue] == 2;
    NSString *text; UIColor *color;
    if (stopOK && inflowOK) { text = @"三项都支持：停充与禁流都可用"; color = [UIColor systemGreenColor]; }
    else if (smartOnly) { text = @"只有智能停充可用：建议在充电高级里打开智能停充"; color = [UIColor systemOrangeColor]; }
    else if ((stopTested || smartTested) && stopUnsupported && inflowTested && inflowUnsupported) { text = @"停充与禁流都不支持：本机暂不支持充电控制"; color = [UIColor systemRedColor]; }
    else { text = @"部分能力可用：请结合探针结果再判断"; color = [UIColor systemOrangeColor]; }
    _overallLabel.text = text;
    _overallLabel.textColor = color;
}

- (void)probeTapped {
    if (_probeRunning || _engineRunning) { return; }
    __weak typeof(self) weakSelf = self;
    UIAlertController *confirm = [UIAlertController alertControllerWithTitle:@"运行停充控制探针" message:@"将尝试多种停充写法（每条观察约 2 秒）并自动恢复，整轮约 1–2 分钟。请插着充电器运行。" preferredStyle:UIAlertControllerStyleAlert];
    [confirm addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [confirm addAction:[UIAlertAction actionWithTitle:@"运行" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (strongSelf == nil) { return; }
        strongSelf->_probeRunning = YES;
        [strongSelf updateControls];
        strongSelf->_probeResultLabel.text = @"探针运行中…";
        [[CGDaemonClient shared] runChargeControlProbeWithWaitMs:2000 restore:YES completion:^(NSDictionary *response, NSError *error) {
            dispatch_async(dispatch_get_main_queue(), ^{
                __strong typeof(weakSelf) strongSelf2 = weakSelf;
                if (strongSelf2 == nil) { return; }
                strongSelf2->_probeRunning = NO;
                [strongSelf2 updateControls];
                if (error != nil || response == nil || [response[@"status"] intValue] != 0) {
                    strongSelf2->_probeResultLabel.text = [NSString stringWithFormat:@"探针失败：%@", error.localizedDescription ?: [response[@"msg"] description] ?: @"守护进程未响应"];
                    return;
                }
                NSDictionary *data = [response[@"data"] isKindOfClass:[NSDictionary class]] ? response[@"data"] : nil;
                [strongSelf2 applyProbePayload:data];
            });
        }];
    }]];
    [self presentViewController:confirm animated:YES completion:nil];
}

- (void)applyProbePayload:(NSDictionary *)data {
    for (UIView *view in _probeStack.arrangedSubviews) {
        [_probeStack removeArrangedSubview:view];
        [view removeFromSuperview];
    }
    if (![data isKindOfClass:[NSDictionary class]]) {
        _probeResultLabel.text = @"探针没有返回可用数据。";
        return;
    }
    NSDictionary *summary = [data[@"summary"] isKindOfClass:[NSDictionary class]] ? data[@"summary"] : @{};
    if ([summary[@"baseline_invalid"] boolValue]) {
        _probeResultLabel.text = @"探针基线无效：开始时未在充电，请在真充电时重跑。";
    } else if ([summary[@"any_effective"] boolValue]) {
        NSString *best = summary[@"best_path"];
        _probeResultLabel.text = [NSString stringWithFormat:@"发现有效停充路径：%@", [best isKindOfClass:[NSString class]] && best.length > 0 ? best : @"已找到"];
    } else {
        NSString *dominant = summary[@"dominant_failure"];
        _probeResultLabel.text = [NSString stringWithFormat:@"未发现有效停充路径%@", [dominant isKindOfClass:[NSString class]] && dominant.length > 0 ? [NSString stringWithFormat:@"（主要失败原因：%@）", dominant] : @""];
    }
    NSArray *results = [data[@"results"] isKindOfClass:[NSArray class]] ? data[@"results"] : @[];
    NSInteger index = 0;
    for (NSDictionary *item in results) {
        if (![item isKindOfClass:[NSDictionary class]]) { continue; }
        NSString *name = CGProbePathName(item[@"service"], item[@"path"], index);
        NSString *verdict = CGProbeVerdictText(item);
        NSString *write = (item[@"write_ret"] != nil && [item[@"write_ret"] integerValue] != 0) ? @"写入失败" : @"写入成功";
        NSString *stopped = [item[@"current_stopped"] boolValue] ? @"电流已停" : @"电流未停";
        [_probeStack addArrangedSubview:CGCardLabel([NSString stringWithFormat:@"%@：%@（%@，%@）", name, verdict, write, stopped], 14, UIFontWeightRegular, [UIColor labelColor])];
        index += 1;
    }
    if (index == 0) {
        [_probeStack addArrangedSubview:CGCardLabel(@"探针没有返回逐路径结果。", 14, UIFontWeightRegular, [UIColor secondaryLabelColor])];
    }
}

@end

#pragma mark - Advanced

@implementation CGAdvancedViewController {
    NSMutableDictionary<NSNumber *, UISwitch *> *_switches;
    NSMutableDictionary<NSNumber *, NSString *> *_switchKeys;
    NSMutableDictionary<NSString *, UILabel *> *_valueLabels;
    NSDictionary *_raw;
    CGConfig *_config;
    UILabel *_offlineLabel;
    UILabel *_diagLabel;
    UILabel *_probeResultLabel;
    NSString *_probeSummary;
    BOOL _probeRunning;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor systemGroupedBackgroundColor];
    self.title = @"充电高级";
    _switches = [NSMutableDictionary dictionary];
    _switchKeys = [NSMutableDictionary dictionary];
    _valueLabels = [NSMutableDictionary dictionary];
    _offlineLabel = CGCardLabel(@"正在读取配置…", 14, UIFontWeightRegular, [UIColor secondaryLabelColor]);
    _diagLabel = CGCardLabel(@"正在读取诊断…", 14, UIFontWeightRegular, [UIColor labelColor]);
    _probeResultLabel = CGCardLabel(@"还没跑过探针。", 14, UIFontWeightRegular, [UIColor secondaryLabelColor]);
    UIStackView *stack = CGVerticalStack(@[]);
    [stack addArrangedSubview:CGBackButton(self, @selector(cgGoBack))];
    [stack addArrangedSubview:CGCardLabel(@"充电高级", 24, UIFontWeightBold, [UIColor labelColor])];
    [stack addArrangedSubview:_offlineLabel];
    [stack addArrangedSubview:CGCardWithStack(CGVerticalStack(@[
        [self advSwitchRow:1 title:@"完整控制" subtitle:@"主开关：关掉后守护进程不驻留，全部停充控制停止" key:@"enable"],
        [self advSwitchRow:2 title:@"高温停充" subtitle:@"温度达到高温阈值时停充，降温后恢复" key:@"enable_temp"],
        [self advSwitchRow:3 title:@"智能停充" subtitle:@"停充时先用预测式抑制；不生效时自动回退到传统停充" key:@"adv_predictive_inhibit_charge"],
    ]))];
    [stack addArrangedSubview:CGCardWithStack(CGVerticalStack(@[
        [self advSwitchRow:4 title:@"100% 时交由系统控制" subtitle:@"开：到 100% 后由系统接管上限，本工具只保留温度停充" key:@"adv_system_capacity_control_at_100"],
        [self advSwitchRow:5 title:@"停充时禁流" subtitle:@"停充时禁止电流流入设备，改由电池放电供电" key:@"adv_disable_inflow"],
        [self advSwitchRow:6 title:@"插电保持" subtitle:@"围绕停充目标维持一个缓冲区间，长时间插电时少补电" key:@"adv_hold_enabled"],
        CGValueRow(@"补电阈值", @"—", self, @selector(pickerTapped:), 101, _valueLabels, @"holdBand"),
        CGValueRow(@"检查间隔", @"—", self, @selector(pickerTapped:), 102, _valueLabels, @"holdInterval"),
    ]))];
    [stack addArrangedSubview:CGCardWithStack(CGVerticalStack(@[
        [self advSwitchRow:7 title:@"加速充电" subtitle:@"充电时关掉部分耗电功能，充得更快" key:@"acc_charge"],
        [self advSwitchRow:8 title:@"飞行模式" subtitle:@"加速充电时同步执行" key:@"acc_charge_airmode"],
        [self advSwitchRow:9 title:@"关闭 WiFi" subtitle:@"加速充电时同步执行" key:@"acc_charge_wifi"],
        [self advSwitchRow:10 title:@"关闭蓝牙" subtitle:@"加速充电时同步执行" key:@"acc_charge_blue"],
        [self advSwitchRow:11 title:@"降低亮度" subtitle:@"加速充电时同步执行" key:@"acc_charge_bright"],
        [self advSwitchRow:12 title:@"低电量模式" subtitle:@"加速充电时同步执行" key:@"acc_charge_lpm"],
    ]))];
    [stack addArrangedSubview:CGCardWithStack(CGVerticalStack(@[
        CGValueRow(@"充电时档位", @"—", self, @selector(pickerTapped:), 103, _valueLabels, @"chargeThermal"),
        CGValueRow(@"平时档位", @"—", self, @selector(pickerTapped:), 104, _valueLabels, @"idleThermal"),
        CGValueRow(@"当前生效档位", @"—", nil, NULL, 0, _valueLabels, @"activeScope"),
        CGCardLabel(@"充电时档位与平时档位共用同一个温度模拟通道：插电充电时用前者，其余时间用后者，不会同时生效。主开关关掉或仅限流模式下，这一组不可改。", 13, UIFontWeightRegular, [UIColor secondaryLabelColor]),
    ]))];
    [stack addArrangedSubview:CGCardWithStack(CGVerticalStack(@[
        [self advSwitchRow:13 title:@"永久停用系统优化充电" subtitle:@"直接关掉系统的优化充电策略" key:@"disable_smart_charge"],
        [self advSwitchRow:14 title:@"插电保持时临时停用" subtitle:@"只在保持或停充阶段暂时停用，退出后尝试恢复" key:@"adv_hold_temp_disable_smart_charge"],
        CGTextButton(@"还原系统优化充电", self, @selector(restoreSmartTapped)),
    ]))];
    [stack addArrangedSubview:CGCardWithStack(CGVerticalStack(@[
        [self advSwitchRow:15 title:@"启用满充计划" subtitle:@"每隔几天在指定时间暂时解除电量上限；温度控制仍保留" key:@"full_charge_sched_enabled"],
        CGValueRow(@"每隔天数", @"—", self, @selector(pickerTapped:), 105, _valueLabels, @"schedInterval"),
        CGValueRow(@"开始时间", @"—", self, @selector(pickerTapped:), 106, _valueLabels, @"schedStart"),
        CGValueRow(@"持续时长", @"—", self, @selector(pickerTapped:), 107, _valueLabels, @"schedDuration"),
    ]))];
    [stack addArrangedSubview:CGCardWithStack(CGVerticalStack(@[
        CGCardLabel(@"当前状态与诊断", 17, UIFontWeightBold, [UIColor labelColor]),
        _diagLabel,
        CGTextButton(@"运行停充控制探针", self, @selector(advProbeTapped)),
        _probeResultLabel,
        CGTextButton(@"复制诊断摘要", self, @selector(copyDiagTapped)),
    ]))];
    UIButton *resetButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [resetButton setTitle:@"重置所有设置" forState:UIControlStateNormal];
    [resetButton setTitleColor:[UIColor systemRedColor] forState:UIControlStateNormal];
    resetButton.titleLabel.font = [UIFont systemFontOfSize:17];
    [resetButton addTarget:self action:@selector(resetTapped) forControlEvents:UIControlEventTouchUpInside];
    [stack addArrangedSubview:resetButton];
    CGAddScrollStack(self, stack);
    [self refreshAdvanced];
}

- (UIView *)advSwitchRow:(NSInteger)tag title:(NSString *)title subtitle:(NSString *)subtitle key:(NSString *)key {
    UISwitch *sw = [[UISwitch alloc] init];
    sw.enabled = NO;
    sw.tag = tag;
    [sw addTarget:self action:@selector(advSwitchChanged:) forControlEvents:UIControlEventValueChanged];
    _switches[@(tag)] = sw;
    _switchKeys[@(tag)] = key;
    return CGSwitchRow(title, subtitle, sw);
}

- (void)cgGoBack {
    [self.navigationController popViewControllerAnimated:YES];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self refreshAdvanced];
}

- (void)refreshAdvanced {
    __weak typeof(self) weakSelf = self;
    [[CGDaemonClient shared] fetchConfigWithCompletion:^(CGConfig *config, NSError *error) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (strongSelf == nil) { return; }
        if (config == nil) {
            strongSelf->_offlineLabel.text = @"守护进程离线：开关未读取到配置，暂不可改动。";
            return;
        }
        strongSelf->_offlineLabel.hidden = YES;
        strongSelf->_config = config;
        strongSelf->_raw = config.rawDaemonDictionary ?: @{};
        [strongSelf applyRawToUI];
        [[CLBatteryManager shared] refreshConfig];
    }];
    [[CGDaemonClient shared] fetchDiagnosticsWithCompletion:^(NSDictionary *diag, NSError *error) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (strongSelf == nil) { return; }
        [strongSelf updateDiagLabelWithDiagnostics:diag error:error];
    }];
}

- (void)applyRawToUI {
    NSDictionary *raw = _raw ?: @{};
    // Missing-key defaults mirror the daemon/app defaults: smart stop and
    // 100%-system-control default on, everything else defaults off.
    _switches[@1].on = CGBoolFromRaw(raw, @"enable", YES);
    _switches[@2].on = CGBoolFromRaw(raw, @"enable_temp", YES);
    _switches[@3].on = CGBoolFromRaw(raw, @"adv_predictive_inhibit_charge", YES);
    _switches[@4].on = CGBoolFromRaw(raw, @"adv_system_capacity_control_at_100", YES);
    _switches[@5].on = CGBoolFromRaw(raw, @"adv_disable_inflow", NO);
    _switches[@6].on = CGBoolFromRaw(raw, @"adv_hold_enabled", NO);
    _switches[@7].on = CGBoolFromRaw(raw, @"acc_charge", NO);
    _switches[@8].on = CGBoolFromRaw(raw, @"acc_charge_airmode", NO);
    _switches[@9].on = CGBoolFromRaw(raw, @"acc_charge_wifi", NO);
    _switches[@10].on = CGBoolFromRaw(raw, @"acc_charge_blue", NO);
    _switches[@11].on = CGBoolFromRaw(raw, @"acc_charge_bright", NO);
    _switches[@12].on = CGBoolFromRaw(raw, @"acc_charge_lpm", NO);
    _switches[@13].on = CGBoolFromRaw(raw, @"disable_smart_charge", NO);
    _switches[@14].on = CGBoolFromRaw(raw, @"adv_hold_temp_disable_smart_charge", NO);
    _switches[@15].on = CGBoolFromRaw(raw, @"full_charge_sched_enabled", NO);
    for (UISwitch *sw in _switches.allValues) { sw.enabled = YES; }
    NSInteger band = CGIntFromRaw(raw, @"adv_hold_band", 2);
    NSInteger interval = CGIntFromRaw(raw, @"adv_hold_check_interval_minutes", 5);
    _valueLabels[@"holdBand"].text = [NSString stringWithFormat:@"%ld%%", (long)MAX(1, band)];
    _valueLabels[@"holdInterval"].text = [NSString stringWithFormat:@"%ld 分钟", (long)MAX(1, interval)];
    BOOL limitOn = CGBoolFromRaw(raw, @"adv_limit_inflow", NO);
    NSInteger chargeMode = CGThermalModeFromValue(raw[@"adv_limit_inflow_mode"]);
    _valueLabels[@"chargeThermal"].text = limitOn ? CGThermalModeName(chargeMode) : @"关闭";
    _valueLabels[@"idleThermal"].text = CGThermalModeName(CGThermalModeFromValue(raw[@"adv_def_thermal_mode"]));
    NSInteger schedDays = CGIntFromRaw(raw, @"full_charge_sched_interval_days", 7);
    NSInteger startMin = CGIntFromRaw(raw, @"full_charge_sched_start_minute", 120);
    NSInteger durHours = CGIntFromRaw(raw, @"full_charge_sched_duration_hours", 4);
    _valueLabels[@"schedInterval"].text = [NSString stringWithFormat:@"%ld 天", (long)MAX(1, schedDays)];
    _valueLabels[@"schedStart"].text = [NSString stringWithFormat:@"%02ld:%02ld", (long)(startMin / 60), (long)(startMin % 60)];
    _valueLabels[@"schedDuration"].text = [NSString stringWithFormat:@"%ld 小时", (long)MAX(1, durHours)];
    [self applyInterlockStates];
    // Active scope is a daemon verdict, not a derivation: show it only
    // when the manager has one, otherwise a dash (never an invented level).
    CLBatteryManager *manager = [CLBatteryManager shared];
    NSString *scope = manager.thermalActiveScope;
    if (!_switches[@1].on || [self isLimitOnly]) {
        _valueLabels[@"activeScope"].text = @"—（当前不可用）";
    } else if ([scope isEqualToString:@"charging"]) {
        _valueLabels[@"activeScope"].text = [NSString stringWithFormat:@"充电时档位 · %@", _valueLabels[@"chargeThermal"].text];
    } else if ([scope isEqualToString:@"idle"]) {
        _valueLabels[@"activeScope"].text = [NSString stringWithFormat:@"平时档位 · %@", _valueLabels[@"idleThermal"].text];
    } else {
        _valueLabels[@"activeScope"].text = @"—";
    }
}

- (BOOL)isLimitOnly {
    return CGBoolFromRaw(_raw ?: @{}, @"limit_only_mode", NO);
}

- (void)applyInterlockStates {
    BOOL accOn = _switches[@7].on;
    for (NSInteger tag = 8; tag <= 12; tag++) { _switches[@(tag)].enabled = accOn; }
    BOOL holdBlocked = (_config != nil && _config.stopChargeAbove == 100 && _switches[@4].on);
    _switches[@6].enabled = !holdBlocked;
    BOOL thermalLocked = !_switches[@1].on || [self isLimitOnly];
    // Thermal picker rows are the value rows; their overlay buttons are
    // disabled by dimming the labels (taps still land, so guard in handler).
    _valueLabels[@"chargeThermal"].alpha = thermalLocked ? 0.4 : 1.0;
    _valueLabels[@"idleThermal"].alpha = thermalLocked ? 0.4 : 1.0;
    _switches[@14].enabled = !_switches[@13].on;
}

- (void)advSwitchChanged:(UISwitch *)sender {
    NSString *key = _switchKeys[@(sender.tag)];
    if (key == nil) { return; }
    BOOL newValue = sender.on;
    // Interlock guards, mirroring the old page: a switch that cannot take
    // effect in the current combination is reverted with an explanation,
    // never silently left on.
    if (sender.tag == 6 && _config != nil && _config.stopChargeAbove == 100 && _switches[@4].on) {
        sender.on = NO;
        CGShowAlert(self, @"插电保持暂不可用", @"停充上限已是 100% 且 100% 已交由系统控制，插电保持暂时停用；把上限调回 100% 以下或关掉系统接管后会自动恢复。");
        return;
    }
    __weak typeof(self) weakSelf = self;
    [[CGDaemonClient shared] setConfigValue:@(newValue) forKey:key completion:^(BOOL success, NSError *error) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (strongSelf == nil) { return; }
        if (!success) {
            sender.on = !newValue;
            CGShowAlert(strongSelf, @"保存失败", error.localizedDescription.length > 0 ? error.localizedDescription : @"守护进程未接受这次修改，开关已恢复。");
            return;
        }
        // Interlock side-writes, same as the old page.
        if (sender.tag == 3 && newValue && strongSelf->_switches[@5].on) {
            strongSelf->_switches[@5].on = NO;
            [[CGDaemonClient shared] setConfigValue:@NO forKey:@"adv_disable_inflow" completion:nil];
        } else if (sender.tag == 5 && newValue && strongSelf->_switches[@6].on) {
            strongSelf->_switches[@6].on = NO;
            [[CGDaemonClient shared] setConfigValue:@NO forKey:@"adv_hold_enabled" completion:nil];
        } else if (sender.tag == 13 && newValue && strongSelf->_switches[@14].on) {
            strongSelf->_switches[@14].on = NO;
            [[CGDaemonClient shared] setConfigValue:@NO forKey:@"adv_hold_temp_disable_smart_charge" completion:nil];
        }
        [[CLBatteryManager shared] refreshConfig];
        [strongSelf applyInterlockStates];
    }];
}

- (void)pickerTapped:(UIButton *)sender {
    NSInteger tag = sender.tag;
    if ((tag == 103 || tag == 104) && (!_switches[@1].on || [self isLimitOnly])) {
        CGShowAlert(self, @"档位暂不可改", !_switches[@1].on ? @"完整控制已关，温度模拟通道不归本页管。" : @"仅限流模式下温度模拟通道不归本页管。");
        return;
    }
    __weak typeof(self) weakSelf = self;
    void (^writeInt)(NSString *, NSInteger) = ^(NSString *key, NSInteger value) {
        [[CGDaemonClient shared] setConfigValue:@(value) forKey:key completion:^(BOOL success, NSError *error) {
            __strong typeof(weakSelf) strongSelf = weakSelf;
            if (strongSelf == nil) { return; }
            if (success) { [strongSelf refreshAdvanced]; }
            else { CGShowAlert(strongSelf, @"保存失败", error.localizedDescription.length > 0 ? error.localizedDescription : @"守护进程未接受这次修改。"); }
        }];
    };
    if (tag == 101) {
        [self presentIntegerInputWithTitle:@"补电阈值" message:@"请输入 1 ~ 10 之间的百分比。达到目标后，电量低于这个阈值时才会恢复补电。" current:CGIntFromRaw(_raw ?: @{}, @"adv_hold_band", 2) min:1 max:10 completion:^(NSInteger value) { writeInt(@"adv_hold_band", value); }];
    } else if (tag == 102) {
        [self presentIntegerInputWithTitle:@"检查间隔" message:@"请输入 1 ~ 10 之间的分钟数。达到保持目标后，会按这个间隔检查一次是否需要恢复补电。" current:CGIntFromRaw(_raw ?: @{}, @"adv_hold_check_interval_minutes", 5) min:1 max:10 completion:^(NSInteger value) { writeInt(@"adv_hold_check_interval_minutes", value); }];
    } else if (tag == 103) {
        [self presentThermalPickerWithTitle:@"充电时档位" message:@"插电充电时生效；档位越高，充电电流越小。" currentMode:CGThermalModeFromValue(_raw[@"adv_limit_inflow_mode"]) isCharge:YES];
    } else if (tag == 104) {
        [self presentThermalPickerWithTitle:@"平时档位" message:@"未插电或未充电时生效；档位越高，性能越低，发热越少。" currentMode:CGThermalModeFromValue(_raw[@"adv_def_thermal_mode"]) isCharge:NO];
    } else if (tag == 105) {
        [self presentIntegerInputWithTitle:@"每隔天数" message:@"请输入 1 ~ 90 之间的天数。" current:CGIntFromRaw(_raw ?: @{}, @"full_charge_sched_interval_days", 7) min:1 max:90 completion:^(NSInteger value) { writeInt(@"full_charge_sched_interval_days", value); }];
    } else if (tag == 106) {
        NSInteger startMin = CGIntFromRaw(_raw ?: @{}, @"full_charge_sched_start_minute", 120);
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"开始时间" message:@"请分别输入小时和分钟。" preferredStyle:UIAlertControllerStyleAlert];
        [alert addTextFieldWithConfigurationHandler:^(UITextField *textField) { textField.placeholder = @"小时"; textField.text = [NSString stringWithFormat:@"%ld", (long)(startMin / 60)]; textField.keyboardType = UIKeyboardTypeNumberPad; textField.textAlignment = NSTextAlignmentCenter; }];
        [alert addTextFieldWithConfigurationHandler:^(UITextField *textField) { textField.placeholder = @"分钟"; textField.text = [NSString stringWithFormat:@"%02ld", (long)(startMin % 60)]; textField.keyboardType = UIKeyboardTypeNumberPad; textField.textAlignment = NSTextAlignmentCenter; }];
        [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
        [alert addAction:[UIAlertAction actionWithTitle:@"确定" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
            NSInteger hour = MAX(0, MIN(23, [alert.textFields.firstObject.text integerValue]));
            NSInteger minute = MAX(0, MIN(59, [alert.textFields.lastObject.text integerValue]));
            writeInt(@"full_charge_sched_start_minute", hour * 60 + minute);
        }]];
        [self presentViewController:alert animated:YES completion:nil];
    } else if (tag == 107) {
        [self presentIntegerInputWithTitle:@"持续时长" message:@"请输入 1 ~ 12 之间的小时数。" current:CGIntFromRaw(_raw ?: @{}, @"full_charge_sched_duration_hours", 4) min:1 max:12 completion:^(NSInteger value) { writeInt(@"full_charge_sched_duration_hours", value); }];
    }
}

- (void)presentIntegerInputWithTitle:(NSString *)title message:(NSString *)message current:(NSInteger)current min:(NSInteger)min max:(NSInteger)max completion:(void (^)(NSInteger))completion {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:title message:message preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *textField) { textField.text = [NSString stringWithFormat:@"%ld", (long)current]; textField.keyboardType = UIKeyboardTypeNumberPad; textField.textAlignment = NSTextAlignmentCenter; }];
    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    __weak typeof(self) weakSelf = self;
    [alert addAction:[UIAlertAction actionWithTitle:@"确定" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        NSInteger value = [alert.textFields.firstObject.text integerValue];
        if (value < min || value > max) {
            CGShowAlert(weakSelf, @"数值超出范围", [NSString stringWithFormat:@"请输入 %ld ~ %ld 之间的数值，未写入。", (long)min, (long)max]);
            return;
        }
        if (completion != nil) { completion(value); }
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)presentThermalPickerWithTitle:(NSString *)title message:(NSString *)message currentMode:(NSInteger)currentMode isCharge:(BOOL)isCharge {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:title message:message preferredStyle:UIAlertControllerStyleAlert];
    __weak typeof(self) weakSelf = self;
    for (NSInteger mode = 0; mode <= 4; mode++) {
        NSString *name = CGThermalModeName(mode);
        NSString *display = mode == currentMode ? [NSString stringWithFormat:@"%@（当前）", name] : name;
        [alert addAction:[UIAlertAction actionWithTitle:display style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
            __strong typeof(weakSelf) strongSelf = weakSelf;
            if (strongSelf == nil) { return; }
            if (isCharge) {
                [[CGDaemonClient shared] setLimitInflowEnabled:(mode != 0) mode:CGThermalModeValue(mode) completion:^(BOOL success, NSError *error) {
                    if (success) { [strongSelf refreshAdvanced]; }
                    else { CGShowAlert(strongSelf, @"保存失败", error.localizedDescription.length > 0 ? error.localizedDescription : @"守护进程未接受这次修改。"); }
                }];
            } else {
                [[CGDaemonClient shared] setConfigValue:CGThermalModeValue(mode) forKey:@"adv_def_thermal_mode" completion:^(BOOL success, NSError *error) {
                    if (success) { [strongSelf refreshAdvanced]; }
                    else { CGShowAlert(strongSelf, @"保存失败", error.localizedDescription.length > 0 ? error.localizedDescription : @"守护进程未接受这次修改。"); }
                }];
            }
        }]];
    }
    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)restoreSmartTapped {
    __weak typeof(self) weakSelf = self;
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"还原系统优化充电" message:@"清除本工具残留的停用状态，恢复系统优化充电与充电控制。" preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"还原" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        [[CGDaemonClient shared] restoreSmartChargeWithCompletion:^(NSDictionary *response, NSError *error) {
            __strong typeof(weakSelf) strongSelf = weakSelf;
            if (strongSelf == nil) { return; }
            NSDictionary *data = [response[@"data"] isKindOfClass:[NSDictionary class]] ? response[@"data"] : @{};
            NSInteger after = [data[@"after_status"] integerValue];
            BOOL ok = (error == nil && [response[@"status"] intValue] == 0 && (after == 1 || after == 2));
            CGShowAlert(strongSelf, ok ? @"还原成功" : @"还原失败", ok ? @"系统优化充电已恢复。若系统设置中的选项仍异常，请重启设备后再试。" : (error == nil && [response[@"status"] intValue] == 0 ? @"还原命令已执行，但系统优化充电状态未变化，请重启设备后再试。" : [NSString stringWithFormat:@"操作失败：%@", error.localizedDescription ?: @"无法连接守护进程"]));
            if (ok) { [strongSelf refreshAdvanced]; }
        }];
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)resetTapped {
    __weak typeof(self) weakSelf = self;
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"重置所有设置" message:@"将恢复守护进程的默认配置，当前全部高级设置都会被覆盖。确定要重置吗？" preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"重置" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action) {
        [[CGDaemonClient shared] resetConfigWithCompletion:^(BOOL success, NSError *error) {
            __strong typeof(weakSelf) strongSelf = weakSelf;
            if (strongSelf == nil) { return; }
            if (success) { [strongSelf refreshAdvanced]; }
            else { CGShowAlert(strongSelf, @"重置失败", error.localizedDescription.length > 0 ? error.localizedDescription : @"守护进程未接受重置。"); }
        }];
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)updateDiagLabelWithDiagnostics:(NSDictionary *)diag error:(NSError *)error {
    CLBatteryManager *manager = [CLBatteryManager shared];
    NSMutableString *text = [NSMutableString string];
    if (_config != nil) {
        [text appendFormat:@"停充上限 %ld%%，开始充电 ≤%ld%%，高温停充 ≥%ld℃，降温恢复 ≤%ld℃。\n",
         (long)_config.stopChargeAbove, (long)_config.startChargeBelow, (long)_config.tempAbove, (long)_config.tempBelow];
    }
    [text appendFormat:@"当前电量 %ld%%，温度 %.1f℃，%@。\n",
     (long)manager.currentCapacity, manager.temperature,
     manager.isCharging ? @"正在充电" : @"未在充电"];
    NSInteger band = CGIntFromRaw(_raw ?: @{}, @"adv_hold_band", 2);
    if (_config != nil && _switches[@6].on) {
        [text appendFormat:@"插电保持：目标 %ld%%，低于 %ld%% 时补电。\n", (long)_config.stopChargeAbove, (long)MAX(0, _config.stopChargeAbove - band)];
    }
    if (error != nil || diag == nil) {
        [text appendString:@"守护进程诊断数据读取失败。"];
    } else {
        NSDictionary *data = [diag[@"data"] isKindOfClass:[NSDictionary class]] ? diag[@"data"] : diag;
        [text appendFormat:@"守护进程诊断已读取（%ld 项）。", (long)data.count];
    }
    _diagLabel.text = [text copy];
}

- (void)advProbeTapped {
    if (_probeRunning) { return; }
    __weak typeof(self) weakSelf = self;
    UIAlertController *confirm = [UIAlertController alertControllerWithTitle:@"运行停充控制探针" message:@"将尝试多种停充写法（每条观察约 2 秒）并自动恢复，整轮约 1–2 分钟。请插着充电器运行。" preferredStyle:UIAlertControllerStyleAlert];
    [confirm addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [confirm addAction:[UIAlertAction actionWithTitle:@"运行" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (strongSelf == nil) { return; }
        strongSelf->_probeRunning = YES;
        strongSelf->_probeResultLabel.text = @"探针运行中…";
        [[CGDaemonClient shared] runChargeControlProbeWithWaitMs:2000 restore:YES completion:^(NSDictionary *response, NSError *error) {
            __strong typeof(weakSelf) strongSelf2 = weakSelf;
            if (strongSelf2 == nil) { return; }
            strongSelf2->_probeRunning = NO;
            if (error != nil || response == nil || [response[@"status"] intValue] != 0) {
                strongSelf2->_probeResultLabel.text = [NSString stringWithFormat:@"探针失败：%@", error.localizedDescription ?: @"守护进程未响应"];
                return;
            }
            NSDictionary *data = [response[@"data"] isKindOfClass:[NSDictionary class]] ? response[@"data"] : nil;
            NSDictionary *summary = [data[@"summary"] isKindOfClass:[NSDictionary class]] ? data[@"summary"] : @{};
            NSMutableString *summaryText = [NSMutableString stringWithString:@"停充控制探针结果\n"];
            if ([summary[@"baseline_invalid"] boolValue]) {
                [summaryText appendString:@"基线无效：开始时未在充电，请在真充电时重跑。\n"];
            } else if ([summary[@"any_effective"] boolValue]) {
                [summaryText appendFormat:@"发现有效路径：%@\n", summary[@"best_path"] ?: @"已找到"];
            } else {
                [summaryText appendFormat:@"未发现有效路径：%@\n", summary[@"dominant_failure"] ?: @"—"];
            }
            NSArray *results = [data[@"results"] isKindOfClass:[NSArray class]] ? data[@"results"] : @[];
            NSInteger index = 0;
            for (NSDictionary *item in results) {
                if (![item isKindOfClass:[NSDictionary class]]) { continue; }
                [summaryText appendFormat:@"%@：%@（%@，%@）\n", CGProbePathName(item[@"service"], item[@"path"], index), CGProbeVerdictText(item),
                 (item[@"write_ret"] != nil && [item[@"write_ret"] integerValue] != 0) ? @"写入失败" : @"写入成功",
                 [item[@"current_stopped"] boolValue] ? @"电流已停" : @"电流未停"];
                index += 1;
            }
            strongSelf2->_probeSummary = [summaryText copy];
            if ([summary[@"baseline_invalid"] boolValue]) {
                strongSelf2->_probeResultLabel.text = @"探针基线无效：开始时未在充电，请在真充电时重跑。";
            } else if ([summary[@"any_effective"] boolValue]) {
                strongSelf2->_probeResultLabel.text = [NSString stringWithFormat:@"发现有效停充路径：%@", summary[@"best_path"] ?: @"已找到"];
            } else {
                strongSelf2->_probeResultLabel.text = @"未发现有效停充路径。点“复制诊断摘要”可把逐路径结果复制出来。";
            }
        }];
    }]];
    [self presentViewController:confirm animated:YES completion:nil];
}

- (void)copyDiagTapped {
    NSMutableString *text = [NSMutableString stringWithString:_diagLabel.text ?: @""];
    if (_probeSummary.length > 0) {
        [text appendFormat:@"\n\n%@", _probeSummary];
    }
    [UIPasteboard generalPasteboard].string = [text copy];
    CGShowAlert(self, @"已复制", @"诊断摘要已复制到剪贴板。");
}

@end

#pragma mark - Software

@implementation CGSoftwareViewController {
    NSMutableDictionary<NSString *, UILabel *> *_valueLabels;
    UISwitch *_notificationSwitch;
    UILabel *_updateLabel;
    UILabel *_dataDirLabel;
    UISlider *_hapticSlider;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor systemGroupedBackgroundColor];
    self.title = @"软件设置";
    _valueLabels = [NSMutableDictionary dictionary];
    NSString *version = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleShortVersionString"] ?: @"?";
    _updateLabel = CGCardLabel(@"还没检查过更新。", 14, UIFontWeightRegular, [UIColor secondaryLabelColor]);
    _notificationSwitch = [[UISwitch alloc] init];
    _notificationSwitch.on = [CLBatteryManager shared].notificationEnabled;
    [_notificationSwitch addTarget:self action:@selector(notificationChanged:) forControlEvents:UIControlEventValueChanged];
    _dataDirLabel = CGCardLabel(@"正在定位数据目录…", 13, UIFontWeightRegular, [UIColor secondaryLabelColor]);
    UIStackView *stack = CGVerticalStack(@[]);
    [stack addArrangedSubview:CGBackButton(self, @selector(cgGoBack))];
    [stack addArrangedSubview:CGCardLabel(@"软件设置", 24, UIFontWeightBold, [UIColor labelColor])];
    [stack addArrangedSubview:CGCardWithStack(CGVerticalStack(@[
        CGCardLabel([NSString stringWithFormat:@"ChargeGuard %@", version], 20, UIFontWeightBold, [UIColor labelColor]),
        CGCardLabel(@"面向 iPhone 的充电控制工具，设上限停充、守温度，延长电池寿命。", 14, UIFontWeightRegular, [UIColor secondaryLabelColor]),
        _updateLabel,
        CGTextButton(@"检查更新", self, @selector(checkUpdateTapped)),
    ]))];
    [stack addArrangedSubview:CGCardWithStack(CGVerticalStack(@[
        CGTextButton(@"导出诊断报告（可分享，不改配置）", self, @selector(exportDiagnostics)),
        CGTextButton(@"复制自动化链接：开始充电", self, @selector(copyChargeURL)),
        CGTextButton(@"复制自动化链接：停止充电", self, @selector(copyNoChargeURL)),
        CGTextButton(@"直接打开：开始充电", self, @selector(openChargeURL)),
        CGTextButton(@"直接打开：停止充电", self, @selector(openNoChargeURL)),
    ]))];
    [stack addArrangedSubview:CGCardWithStack(CGVerticalStack(@[
        CGSwitchRow(@"通知", @"守护进程状态变化时提醒", _notificationSwitch),
        CGValueRow(@"刷新频率", @"—", self, @selector(softwareRowTapped:), 201, _valueLabels, @"refresh"),
        CGCardLabel(@"只影响主界面数据的刷新快慢，不影响后台守护策略。", 13, UIFontWeightRegular, [UIColor secondaryLabelColor]),
        CGValueRow(@"语言", @"—", self, @selector(softwareRowTapped:), 202, _valueLabels, @"language"),
        CGValueRow(@"外观", @"—", self, @selector(softwareRowTapped:), 203, _valueLabels, @"appearance"),
        CGValueRow(@"停充预设快捷值", @"—", self, @selector(softwareRowTapped:), 204, _valueLabels, @"preset"),
        CGValueRow(@"日志级别", @"—", self, @selector(softwareRowTapped:), 205, _valueLabels, @"logLevel"),
    ]))];
    UILabel *hapticTitle = CGCardLabel(@"滑动震动强度", 16, UIFontWeightSemibold, [UIColor labelColor]);
    _hapticSlider = [[UISlider alloc] init];
    _hapticSlider.minimumValue = 0;
    _hapticSlider.maximumValue = 100;
    _hapticSlider.value = [self hapticStyleValue] * 33.0;
    [_hapticSlider addTarget:self action:@selector(hapticSliderChanged:) forControlEvents:UIControlEventValueChanged];
    [stack addArrangedSubview:CGCardWithStack(CGVerticalStack(@[
        hapticTitle,
        CGValueRow(@"震动档位", @"—", self, @selector(softwareRowTapped:), 206, _valueLabels, @"haptic"),
        _hapticSlider,
        CGCardLabel(@"拖动滑块可以试震一下，松手后档位按关闭/轻/中/强就近取整。", 13, UIFontWeightRegular, [UIColor secondaryLabelColor]),
    ]))];
    [stack addArrangedSubview:CGCardWithStack(CGVerticalStack(@[
        CGCardLabel(@"本机数据", 17, UIFontWeightBold, [UIColor labelColor]),
        _dataDirLabel,
        CGTextButton(@"复制数据目录路径", self, @selector(copyDataDirTapped)),
        CGTextButton(@"迁移以前版本的数据", self, @selector(migrateLegacyTapped)),
        CGTextButton(@"删除以前版本的残留文件", self, @selector(cleanupLegacyTapped)),
    ]))];
    CGAddScrollStack(self, stack);
    [self refreshSoftwareRows];
}

- (void)cgGoBack {
    [self.navigationController popViewControllerAnimated:YES];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self refreshSoftwareRows];
}

- (NSInteger)localIntegerForKey:(NSString *)key defaultValue:(NSInteger)fallback {
    id val = getlocalKV_C(key);
    if ([val isKindOfClass:[NSNumber class]]) { return [val integerValue]; }
    return fallback;
}

- (NSInteger)hapticStyleValue {
    NSInteger style = [self localIntegerForKey:@"SliderHapticStyle" defaultValue:0];
    if (style < 0) { style = 0; }
    if (style > 3) { style = 3; }
    return style;
}

- (NSString *)hapticStyleText:(NSInteger)style {
    switch (style) {
        case 0: return @"关闭";
        case 1: return @"轻";
        case 2: return @"中";
        case 3: return @"强";
        default: return @"关闭";
    }
}

- (NSString *)frequencyText:(NSInteger)freq {
    if (freq <= 1) { return @"1 秒"; }
    if (freq <= 20) { return @"20 秒"; }
    if (freq <= 60) { return @"1 分钟"; }
    return @"10 分钟";
}

- (NSString *)languageText {
    switch (CLGetAppLanguage()) {
        case CLAppLanguageEnglish: return @"English";
        case CLAppLanguageChineseSimplified: return @"简体中文";
        default: return @"跟随系统";
    }
}

- (NSString *)appearanceText {
    switch ([self localIntegerForKey:@"AppAppearance" defaultValue:0]) {
        case 1: return @"浅色";
        case 2: return @"深色";
        default: return @"跟随系统";
    }
}

- (NSString *)presetText {
    NSInteger value = [self localIntegerForKey:@"StopChargePresetValue" defaultValue:0];
    if (value <= 0) { return @"未设置"; }
    if (value < 15) { value = 15; }
    if (value > 100) { value = 100; }
    return [NSString stringWithFormat:@"%ld%%", (long)value];
}

- (NSString *)logLevelText {
    NSString *level = getlocalKV_C(@"log_level");
    if ([level isKindOfClass:[NSString class]] && [level isEqualToString:@"error"]) { return @"仅错误"; }
    return @"标准";
}

- (void)refreshSoftwareRows {
    _notificationSwitch.on = [CLBatteryManager shared].notificationEnabled;
    _valueLabels[@"refresh"].text = [self frequencyText:[CLBatteryManager shared].updateFrequency];
    _valueLabels[@"language"].text = [self languageText];
    _valueLabels[@"appearance"].text = [self appearanceText];
    _valueLabels[@"preset"].text = [self presetText];
    _valueLabels[@"logLevel"].text = [self logLevelText];
    _valueLabels[@"haptic"].text = [self hapticStyleText:[self hapticStyleValue]];
    NSString *dir = getRuntimeDataRootPath_C() ?: @"";
    if (dir.length == 0) { dir = getAppDocumentsPath_C() ?: @""; }
    _dataDirLabel.text = dir.length > 0 ? dir : @"未能定位数据目录。";
}

- (void)notificationChanged:(UISwitch *)sender {
    [CLBatteryManager shared].notificationEnabled = sender.on;
}

- (void)softwareRowTapped:(UIButton *)sender {
    NSInteger tag = sender.tag;
    __weak typeof(self) weakSelf = self;
    if (tag == 201) {
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"刷新频率" message:@"影响主页面电池状态、适配器、电池信息等数据的刷新频率，不影响后台守护策略。" preferredStyle:UIAlertControllerStyleActionSheet];
        NSArray *options = @[@1, @20, @60, @600];
        NSArray *titles = @[@"1 秒", @"20 秒", @"1 分钟", @"10 分钟"];
        for (NSInteger i = 0; i < 4; i++) {
            [alert addAction:[UIAlertAction actionWithTitle:titles[(NSUInteger)i] style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
                [CLBatteryManager shared].updateFrequency = [options[(NSUInteger)i] integerValue];
                [weakSelf refreshSoftwareRows];
            }]];
        }
        [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
        [self presentViewController:alert animated:YES completion:nil];
    } else if (tag == 202) {
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"语言" message:nil preferredStyle:UIAlertControllerStyleActionSheet];
        void (^apply)(CLAppLanguage) = ^(CLAppLanguage language) {
            NSError *error = nil;
            if (CLSetAppLanguage(language, &error)) {
                NSString *daemonValue = nil;
                if (language == CLAppLanguageEnglish) { daemonValue = @"en"; }
                else if (language == CLAppLanguageChineseSimplified) { daemonValue = @"zh_CN"; }
                else {
                    NSString *preferred = NSLocale.preferredLanguages.firstObject ?: @"en";
                    daemonValue = [preferred hasPrefix:@"zh"] ? @"zh_CN" : @"en";
                }
                [[CGDaemonClient shared] setConfigValue:daemonValue forKey:@"lang" completion:nil];
                [weakSelf refreshSoftwareRows];
            } else {
                CGShowAlert(weakSelf, @"语言切换失败", error.localizedDescription.length > 0 ? error.localizedDescription : @"未能切换语言。");
            }
        };
        [alert addAction:[UIAlertAction actionWithTitle:@"跟随系统" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) { apply(CLAppLanguageSystem); }]];
        [alert addAction:[UIAlertAction actionWithTitle:@"English" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) { apply(CLAppLanguageEnglish); }]];
        [alert addAction:[UIAlertAction actionWithTitle:@"简体中文" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) { apply(CLAppLanguageChineseSimplified); }]];
        [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
        [self presentViewController:alert animated:YES completion:nil];
    } else if (tag == 203) {
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"外观" message:nil preferredStyle:UIAlertControllerStyleActionSheet];
        void (^apply)(NSInteger, NSString *) = ^(NSInteger style, NSString *label) {
            if (@available(iOS 13.0, *)) {
                weakSelf.view.window.overrideUserInterfaceStyle = (UIUserInterfaceStyle)style;
            }
            setlocalKV_C(@"AppAppearance", @(style));
            (void)label;
            [weakSelf refreshSoftwareRows];
        };
        [alert addAction:[UIAlertAction actionWithTitle:@"跟随系统" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) { apply(0, @"跟随系统"); }]];
        [alert addAction:[UIAlertAction actionWithTitle:@"浅色" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) { apply(1, @"浅色"); }]];
        [alert addAction:[UIAlertAction actionWithTitle:@"深色" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) { apply(2, @"深色"); }]];
        [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
        [self presentViewController:alert animated:YES completion:nil];
    } else if (tag == 204) {
        [self presentIntegerInputForPreset];
    } else if (tag == 205) {
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"日志级别" message:nil preferredStyle:UIAlertControllerStyleActionSheet];
        [alert addAction:[UIAlertAction actionWithTitle:@"标准" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
            setlocalKV_C(@"log_level", @"normal");
            [[CGDaemonClient shared] setConfigValue:@"normal" forKey:@"log_level" completion:nil];
            [weakSelf refreshSoftwareRows];
        }]];
        [alert addAction:[UIAlertAction actionWithTitle:@"仅错误" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
            setlocalKV_C(@"log_level", @"error");
            [[CGDaemonClient shared] setConfigValue:@"error" forKey:@"log_level" completion:nil];
            [weakSelf refreshSoftwareRows];
        }]];
        [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
        [self presentViewController:alert animated:YES completion:nil];
    } else if (tag == 206) {
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"滑动震动强度" message:nil preferredStyle:UIAlertControllerStyleActionSheet];
        NSArray *titles = @[@"关闭", @"轻", @"中", @"强"];
        for (NSInteger i = 0; i < 4; i++) {
            [alert addAction:[UIAlertAction actionWithTitle:titles[(NSUInteger)i] style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
                setlocalKV_C(@"SliderHapticStyle", @(i));
                weakSelf->_hapticSlider.value = i * 33.0;
                [weakSelf refreshSoftwareRows];
            }]];
        }
        [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
        [self presentViewController:alert animated:YES completion:nil];
    }
}

- (void)presentIntegerInputForPreset {
    NSInteger current = [self localIntegerForKey:@"StopChargePresetValue" defaultValue:0];
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"停充预设快捷值" message:@"主界面上限的快捷值；0 表示不设置。请输入 0 或 15 ~ 100 之间的百分比。" preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *textField) { textField.text = [NSString stringWithFormat:@"%ld", (long)current]; textField.keyboardType = UIKeyboardTypeNumberPad; textField.textAlignment = NSTextAlignmentCenter; }];
    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    __weak typeof(self) weakSelf = self;
    [alert addAction:[UIAlertAction actionWithTitle:@"确定" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        NSInteger value = [alert.textFields.firstObject.text integerValue];
        if (value != 0 && (value < 15 || value > 100)) {
            CGShowAlert(weakSelf, @"数值超出范围", @"请输入 0 或 15 ~ 100 之间的数值，未写入。");
            return;
        }
        setlocalKV_C(@"StopChargePresetValue", @(value));
        [weakSelf refreshSoftwareRows];
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)hapticSliderChanged:(UISlider *)sender {
    NSInteger style = (NSInteger)lroundf(sender.value / 33.0);
    if (style < 0) { style = 0; }
    if (style > 3) { style = 3; }
    setlocalKV_C(@"SliderHapticStyle", @(style));
    if (style > 0) {
        if (@available(iOS 10.0, *)) {
            UIImpactFeedbackGenerator *generator = [[UIImpactFeedbackGenerator alloc] initWithStyle:(style == 1 ? UIImpactFeedbackStyleLight : (style == 2 ? UIImpactFeedbackStyleMedium : UIImpactFeedbackStyleHeavy))];
            [generator impactOccurred];
        }
    }
    _valueLabels[@"haptic"].text = [self hapticStyleText:style];
}

- (void)checkUpdateTapped {
    _updateLabel.text = @"正在检查更新…";
    NSString *current = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleShortVersionString"] ?: @"?";
    NSURL *url = [NSURL URLWithString:@"https://api.github.com/repos/xstar68/ChargeGuard/releases/latest"];
    NSURLSessionDataTask *task = [[NSURLSession sharedSession] dataTaskWithURL:url completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (error != nil || data == nil) {
                self->_updateLabel.text = [NSString stringWithFormat:@"检查失败：%@", error.localizedDescription ?: @"网络未响应"];
                return;
            }
            NSError *jsonError = nil;
            NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data options:0 error:&jsonError];
            NSString *tag = [json isKindOfClass:[NSDictionary class]] ? json[@"tag_name"] : nil;
            if (![tag isKindOfClass:[NSString class]] || tag.length == 0) {
                self->_updateLabel.text = @"检查失败：发布页没有返回可用版本。";
                return;
            }
            NSString *latest = [tag hasPrefix:@"v"] ? [tag substringFromIndex:1] : tag;
            if ([latest isEqualToString:current]) {
                self->_updateLabel.text = [NSString stringWithFormat:@"已是最新版本（%@）。", current];
            } else {
                self->_updateLabel.text = [NSString stringWithFormat:@"有新版本 %@（当前 %@）。", latest, current];
                UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"有新版本" message:[NSString stringWithFormat:@"最新版本 %@，当前 %@。", latest, current] preferredStyle:UIAlertControllerStyleAlert];
                [alert addAction:[UIAlertAction actionWithTitle:@"稍后" style:UIAlertActionStyleCancel handler:nil]];
                [alert addAction:[UIAlertAction actionWithTitle:@"打开发布页" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) { [self openReleases]; }]];
                [self presentViewController:alert animated:YES completion:nil];
            }
        });
    }];
    [task resume];
}

- (void)openReleases {
    NSURL *url = [NSURL URLWithString:@"https://github.com/xstar68/ChargeGuard/releases/latest"];
    if (url != nil) {
        [[UIApplication sharedApplication] openURL:url options:@{} completionHandler:nil];
    }
}

- (void)exportDiagnostics {
    __weak typeof(self) weakSelf = self;
    [[CGDaemonClient shared] fetchConfigWithCompletion:^(CGConfig *config, NSError *error) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (strongSelf == nil) { return; }
        if (config == nil) {
            CGShowAlert(strongSelf, @"导出失败", @"未读取到配置，诊断报告无法生成。");
            return;
        }
        [[CGDaemonClient shared] fetchDiagnosticsWithCompletion:^(NSDictionary *diag, NSError *diagError) {
            __strong typeof(weakSelf) strongSelf2 = weakSelf;
            if (strongSelf2 == nil) { return; }
            if (diagError != nil && diag == nil) {
                CGShowAlert(strongSelf2, @"导出失败", @"诊断数据读取失败，未生成空报告。");
                return;
            }
            NSDictionary *battery = nil;
            if ([[CLBatteryManager shared] respondsToSelector:@selector(batteryInfoDictionary)]) {
                battery = [[CLBatteryManager shared] performSelector:@selector(batteryInfoDictionary)];
            }
            if (battery == nil) {
                battery = @{@"CurrentCapacity": @([[CLBatteryManager shared] currentCapacity]),
                            @"Temperature": @([[CLBatteryManager shared] temperature]),
                            @"CycleCount": @([[CLBatteryManager shared] cycleCount]),
                            @"Health": @([[CLBatteryManager shared] health])};
            }
            NSString *version = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleShortVersionString"] ?: @"?";
            NSString *report = [CGDiagnosticsExporter reportWithConfigDictionary:[config daemonDictionary]
                                                                         battery:battery
                                                                     diagnostics:diag
                                                                analyticsSummary:@"由历史统计页生成，明细请在历史统计页查看。"
                                                                         appVersion:version];
            UIActivityViewController *share = [[UIActivityViewController alloc] initWithActivityItems:@[report] applicationActivities:nil];
            [strongSelf2 presentViewController:share animated:YES completion:nil];
        }];
    }];
}

- (void)copyChargeURL {
    [UIPasteboard generalPasteboard].string = [[CGPresetManager chargeURL] absoluteString];
    CGShowAlert(self, @"已复制", @"开始充电的自动化链接已复制。");
}

- (void)copyNoChargeURL {
    [UIPasteboard generalPasteboard].string = [[CGPresetManager noChargeURL] absoluteString];
    CGShowAlert(self, @"已复制", @"停止充电的自动化链接已复制。");
}

- (void)openChargeURL {
    NSURL *url = [CGPresetManager chargeURL];
    [[UIApplication sharedApplication] openURL:url options:@{} completionHandler:nil];
}

- (void)openNoChargeURL {
    NSURL *url = [CGPresetManager noChargeURL];
    [[UIApplication sharedApplication] openURL:url options:@{} completionHandler:nil];
}

- (void)copyDataDirTapped {
    NSString *dir = getRuntimeDataRootPath_C() ?: @"";
    if (dir.length == 0) { dir = getAppDocumentsPath_C() ?: @""; }
    if (dir.length == 0) {
        CGShowAlert(self, @"未能定位", @"未能定位应用数据目录。");
        return;
    }
    [UIPasteboard generalPasteboard].string = dir;
    CGShowAlert(self, @"已复制", @"数据目录路径已复制到剪贴板。");
}

- (void)migrateLegacyTapped {
    NSArray *dirs = getLegacyConfigDirsWithData_C() ?: @[];
    if (dirs.count == 0) {
        CGShowAlert(self, @"未发现以前版本的数据", @"当前未检测到可迁移的以前版本的配置文件。");
        return;
    }
    __weak typeof(self) weakSelf = self;
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"迁移以前版本的数据" message:@"检测到以前版本的配置文件，是否迁移到当前版本的数据目录？迁移会覆盖当前同名文件。" preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"立即迁移" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        NSDictionary *result = migrateLegacyConfigFiles_C() ?: @{};
        CGShowAlert(weakSelf, @"迁移完成", [NSString stringWithFormat:@"新建 %ld，覆盖 %ld，未找到 %ld，失败 %ld。",
         (long)[result[@"migrated"] integerValue], (long)[result[@"replaced"] integerValue],
         (long)[result[@"missing"] integerValue], (long)[result[@"failed"] integerValue]]);
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)cleanupLegacyTapped {
    NSDictionary *result = cleanupLegacyResidualFiles_C() ?: @{};
    CGShowAlert(self, @"清理完成", [NSString stringWithFormat:@"已删除 %ld 个以前版本的残留文件，失败 %ld 个。",
     (long)[result[@"removed"] integerValue], (long)[result[@"failed"] integerValue]]);
}

@end
