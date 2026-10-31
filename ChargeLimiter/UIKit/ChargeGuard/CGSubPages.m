//
//  CGSubPages.m
//  ChargeGuard v3.0 — sub-page implementations.
//

#import "CGSubPages.h"
#import "CGConfig.h"
#import "CGDaemonClient.h"
#import "CGHistoryAnalytics.h"
#import "CGPresetManager.h"
#import "CGDiagnosticsExporter.h"
#import "CGViews.h"
#import "../CLBatteryManager.h"

// Legacy full pages (declared in their .m files, no public headers).
@interface CLHistoryViewController : UIViewController
@end
@interface CLBatteryCompatibilityTestViewController : UIViewController
@end
@interface CLAdvancedSettingsViewController : UIViewController
@end
@interface CLSoftwareSettingsViewController : UIViewController
@end

static UIButton *CGTextButton(NSString *title, id target, SEL action) {
    UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
    button.titleLabel.numberOfLines = 0;
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

static UIView *CGCardWithStack(UIStackView *stack) {
    UIView *card = [[UIView alloc] init];
    card.backgroundColor = [UIColor secondarySystemBackgroundColor];
    card.layer.cornerRadius = 16;
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    [card addSubview:stack];
    [NSLayoutConstraint activateConstraints:@[
        [stack.topAnchor constraintEqualToAnchor:card.topAnchor constant:16],
        [stack.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:16],
        [stack.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-16],
        [stack.bottomAnchor constraintEqualToAnchor:card.bottomAnchor constant:-16],
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
        [stack.topAnchor constraintEqualToAnchor:scroll.topAnchor constant:16],
        [stack.leadingAnchor constraintEqualToAnchor:scroll.leadingAnchor constant:16],
        [stack.trailingAnchor constraintEqualToAnchor:scroll.trailingAnchor constant:-16],
        [stack.bottomAnchor constraintEqualToAnchor:scroll.bottomAnchor constant:-40],
        [stack.widthAnchor constraintEqualToAnchor:scroll.widthAnchor constant:-32],
    ]];
}

#pragma mark - History analytics

@implementation CGHistoryAnalyticsViewController {
    CGCapsuleFilterView *_filter;
    UILabel *_summaryLabel;
    UIStackView *_timelineStack;
    NSArray<NSDictionary *> *_min5Samples;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor systemBackgroundColor];
    self.title = @"历史统计";
    UIStackView *stack = CGVerticalStack(@[]);
    __weak typeof(self) weakSelf = self;
    _filter = [[CGCapsuleFilterView alloc] initWithTitles:@[@"5分钟", @"小时", @"天", @"月"]
                                            selectedIndex:0
                                              changeHandler:^(NSInteger index) {
        [weakSelf refreshAnalytics];
    }];
    _summaryLabel = CGCardLabel(@"正在读取历史数据…", 15, UIFontWeightRegular, [UIColor labelColor]);
    _timelineStack = CGVerticalStack(@[]);
    [stack addArrangedSubview:CGBackButton(self, @selector(cgGoBack))];
    [stack addArrangedSubview:CGCardLabel(@"历史统计 · 新版", 24, UIFontWeightBold, [UIColor labelColor])];
    [stack addArrangedSubview:_filter];
    [stack addArrangedSubview:CGCardWithStack(CGVerticalStack(@[_summaryLabel]))];
    [stack addArrangedSubview:CGCardLabel(@"策略事件时间线（彩色圆点：绿色=停充，橙色=恢复充电，灰色=其他）", 14, UIFontWeightSemibold, [UIColor secondaryLabelColor])];
    [stack addArrangedSubview:CGCardWithStack(_timelineStack)];
    [stack addArrangedSubview:CGTextButton(@"打开完整旧版历史页（图表与全部记录）", self, @selector(openLegacyHistory))];
    CGAddScrollStack(self, stack);
    [self refreshAnalytics];
}

- (void)refreshAnalytics {
    __weak typeof(self) weakSelf = self;
    // Overnight fix: the capsule filter was decorative — selection was never
    // read, so every range showed the same min5 numbers. Now the selected
    // bucket drives the computation, with its own bucket minutes, and the
    // temperature limit comes from the live config, not a hardcoded 40.
    [[CGDaemonClient shared] fetchConfigWithCompletion:^(CGConfig *config, NSError *configError) {
        (void)configError;
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (strongSelf == nil) {
            return;
        }
        double tempLimit = config ? (double)config.tempAbove : 40.0;
        [[CGDaemonClient shared] fetchStatisticsWithCompletion:^(NSDictionary *response, NSError *error) {
            __strong typeof(weakSelf) strongSelf2 = weakSelf;
            if (strongSelf2 == nil) {
                return;
            }
            if (error != nil || response == nil) {
                strongSelf2->_summaryLabel.text = @"历史数据读取失败（守护进程可能离线）。完整旧版页同样依赖同一数据源。";
                return;
            }
            NSDictionary *data = response[@"data"];
            if (![data isKindOfClass:[NSDictionary class]]) {
                data = response;
            }
            NSArray *bucketKeys = @[@"min5", @"hour", @"day", @"month"];
            NSArray *bucketMinutes = @[@5, @60, @1440, @43200];
            NSInteger index = strongSelf2->_filter.selectedIndex;
            if (index < 0 || index >= (NSInteger)bucketKeys.count) { index = 0; }
            NSString *bucketKey = bucketKeys[(NSUInteger)index];
            NSInteger minutes = [bucketMinutes[(NSUInteger)index] integerValue];
            NSArray *samples = [data[bucketKey] isKindOfClass:[NSArray class]] ? data[bucketKey] : @[];
            strongSelf2->_min5Samples = samples;
            double rate = [CGHistoryAnalytics averageChargeRatePercentPerHourFromSamples:samples bucketMinutes:minutes];
            NSInteger span = [CGHistoryAnalytics longestChargingSpanMinutesFromSamples:samples bucketMinutes:minutes];
            NSDictionary *temp = [CGHistoryAnalytics temperatureSummaryFromSamples:samples highTempLimit:tempLimit];
            NSMutableString *summary = [NSMutableString string];
            NSArray *bucketTitles = @[@"5分钟", @"小时", @"天", @"月"];
            [summary appendFormat:@"范围：%@。", bucketTitles[(NSUInteger)index]];
            if (rate > 0) {
                [summary appendFormat:@"充电速度约 %.0f%%/小时；最长连续充电 %ld 分钟。", rate, (long)span];
            } else {
                [summary appendString:@"暂无可用的充电速度样本（需要先开启历史统计并充电一段时间）。"];
            }
            [summary appendFormat:@"\n历史样本最高温度 %.1f℃，≥%.0f℃ 的样本 %ld 条（共 %ld 条）。",
             [temp[@"maxTemperature"] doubleValue], tempLimit, (long)[temp[@"samplesOverLimit"] integerValue], (long)[temp[@"sampleCount"] integerValue]];
            strongSelf2->_summaryLabel.text = [summary copy];
            [strongSelf2 refreshTimeline];
        }];
    }];
}

- (void)refreshTimeline {
    for (UIView *view in _timelineStack.arrangedSubviews) {
        [_timelineStack removeArrangedSubview:view];
        [view removeFromSuperview];
    }
    __weak typeof(self) weakSelf = self;
    [[CGDaemonClient shared] fetchPolicyEventsWithLimit:20 completion:^(NSDictionary *response, NSError *error) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (strongSelf == nil) {
            return;
        }
        NSArray *events = response[@"data"];
        if (![events isKindOfClass:[NSArray class]]) {
            events = response[@"events"];
        }
        if (![events isKindOfClass:[NSArray class]] || events.count == 0) {
            [strongSelf->_timelineStack addArrangedSubview:CGCardLabel(@"暂无策略事件。", 15, UIFontWeightRegular, [UIColor secondaryLabelColor])];
            return;
        }
        for (NSDictionary *event in events) {
            NSString *state = [NSString stringWithFormat:@"%@", event[@"state"] ?: event[@"policyState"] ?: @"?"];
            NSString *reason = [NSString stringWithFormat:@"%@", event[@"reason"] ?: @""];
            UIColor *dotColor = [UIColor systemGrayColor];
            if ([state containsString:@"stop"] || [state containsString:@"停充"]) {
                dotColor = [UIColor systemGreenColor];
            } else if ([state containsString:@"resume"] || [state containsString:@"恢复"]) {
                dotColor = [UIColor systemOrangeColor];
            }
            UIView *dot = [[UIView alloc] init];
            dot.backgroundColor = dotColor;
            dot.layer.cornerRadius = 6;
            [dot.widthAnchor constraintEqualToConstant:12].active = YES;
            [dot.heightAnchor constraintEqualToConstant:12].active = YES;
            UILabel *label = CGCardLabel([NSString stringWithFormat:@"%@  %@", state, reason], 15, UIFontWeightRegular, [UIColor labelColor]);
            UIStackView *row = [[UIStackView alloc] initWithArrangedSubviews:@[dot, label]];
            row.axis = UILayoutConstraintAxisHorizontal;
            row.spacing = 10;
            row.alignment = UIStackViewAlignmentCenter;
            [strongSelf->_timelineStack addArrangedSubview:row];
        }
    }];
}

- (void)cgGoBack {
    [self.navigationController popViewControllerAnimated:YES];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    // A12: returning from a legacy page must re-hide the nav bar (it was
    // unhidden so the legacy page has a visible back button).
    self.navigationController.navigationBarHidden = YES;
}

- (void)openLegacyHistory {
    // A12: legacy pages have no in-content back button and the root hides
    // the nav bar, so without this they are only escapable by edge-swipe.
    self.navigationController.navigationBarHidden = NO;
    [self.navigationController pushViewController:[[CLHistoryViewController alloc] init] animated:YES];
}

@end

#pragma mark - Compat result

@implementation CGCompatResultViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor systemBackgroundColor];
    self.title = @"电池兼容性测试";
    UIStackView *stack = CGVerticalStack(@[]);
    UILabel *conclusion = CGCardLabel(@"未运行", 32, UIFontWeightBold, [UIColor labelColor]);
    UILabel *detail = CGCardLabel(@"新版结论卡：运行完整测试后，这里会显示“设备是否可被 ChargeGuard 支持”的大结论与各路径结果。测试标准不变：停充判定仍用 5mA 严标准（守护进程日常停充标准仍为 120mA，两者不要混淆）。测试本身仍在完整旧版页内运行，结果数据与旧版完全一致。", 15, UIFontWeightRegular, [UIColor labelColor]);
    [stack addArrangedSubview:CGBackButton(self, @selector(cgGoBack))];
    [stack addArrangedSubview:CGCardLabel(@"电池兼容性测试 · 新版", 24, UIFontWeightBold, [UIColor labelColor])];
    [stack addArrangedSubview:CGCardWithStack(CGVerticalStack(@[conclusion, detail]))];
    [stack addArrangedSubview:CGTextButton(@"运行完整兼容性测试（旧版页）", self, @selector(openLegacyCompat))];
    CGAddScrollStack(self, stack);
}

- (void)cgGoBack {
    [self.navigationController popViewControllerAnimated:YES];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    // A12: returning from a legacy page must re-hide the nav bar (it was
    // unhidden so the legacy page has a visible back button).
    self.navigationController.navigationBarHidden = YES;
}

- (void)openLegacyCompat {
    // A12: legacy pages have no in-content back button and the root hides
    // the nav bar, so without this they are only escapable by edge-swipe.
    self.navigationController.navigationBarHidden = NO;
    [self.navigationController pushViewController:[[CLBatteryCompatibilityTestViewController alloc] init] animated:YES];
}

@end

#pragma mark - Advanced

@implementation CGAdvancedViewController {
    UISwitch *_enableSwitch;
    UISwitch *_tempSwitch;
    UISwitch *_smartSwitch;
    UILabel *_offlineLabel;
}

- (UIView *)switchRowWithTitle:(NSString *)title subtitle:(NSString *)subtitle switch:(UISwitch *)sw {
    UILabel *titleLabel = CGCardLabel(title, 16, UIFontWeightSemibold, [UIColor labelColor]);
    UILabel *subtitleLabel = CGCardLabel(subtitle, 13, UIFontWeightRegular, [UIColor secondaryLabelColor]);
    UIStackView *texts = CGVerticalStack(@[titleLabel, subtitleLabel]);
    texts.spacing = 2;
    UIStackView *row = [[UIStackView alloc] initWithArrangedSubviews:@[texts, sw]];
    row.axis = UILayoutConstraintAxisHorizontal;
    row.spacing = 12;
    row.alignment = UIStackViewAlignmentCenter;
    return row;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor systemBackgroundColor];
    self.title = @"充电高级";
    _enableSwitch = [[UISwitch alloc] init];
    _tempSwitch = [[UISwitch alloc] init];
    _smartSwitch = [[UISwitch alloc] init];
    // A6: switches stay disabled until the first confirmed config read —
    // otherwise they render OFF while loading and a tap writes the opposite
    // of the user's intent, or stays OFF forever when offline.
    _enableSwitch.enabled = NO;
    _tempSwitch.enabled = NO;
    _smartSwitch.enabled = NO;
    _offlineLabel = CGCardLabel(@"正在读取配置…", 14, UIFontWeightRegular, [UIColor secondaryLabelColor]);
    [_enableSwitch addTarget:self action:@selector(switchChanged:) forControlEvents:UIControlEventValueChanged];
    [_tempSwitch addTarget:self action:@selector(switchChanged:) forControlEvents:UIControlEventValueChanged];
    [_smartSwitch addTarget:self action:@selector(switchChanged:) forControlEvents:UIControlEventValueChanged];
    _enableSwitch.tag = 1;
    _tempSwitch.tag = 2;
    _smartSwitch.tag = 3;
    UIStackView *stack = CGVerticalStack(@[]);
    [stack addArrangedSubview:CGBackButton(self, @selector(cgGoBack))];
    [stack addArrangedSubview:CGCardLabel(@"充电高级 · 新版", 24, UIFontWeightBold, [UIColor labelColor])];
    [stack addArrangedSubview:CGCardWithStack(CGVerticalStack(@[
        [self switchRowWithTitle:@"完整控制" subtitle:@"主开关：关 = 守护进程不驻留" switch:_enableSwitch],
        [self switchRowWithTitle:@"高温停充" subtitle:@"温度达到阈值时停充" switch:_tempSwitch],
        [self switchRowWithTitle:@"智能停充" subtitle:@"预测式停充，失败时自动回退到传统停充" switch:_smartSwitch],
    ]))];
    [stack addArrangedSubview:_offlineLabel];
    [stack addArrangedSubview:CGCardLabel(@"开关改动会立即经 CGDaemonClient 写守护进程，失败时自动回滚显示值。其余高级选项（插电保持、限流、满充计划、优化充电等）逻辑与默认值不变，见完整旧版页。", 14, UIFontWeightRegular, [UIColor secondaryLabelColor])];
    [stack addArrangedSubview:CGTextButton(@"打开完整旧版高级页", self, @selector(openLegacyAdvanced))];
    CGAddScrollStack(self, stack);
    [self refreshSwitches];
}

- (void)refreshSwitches {
    __weak typeof(self) weakSelf = self;
    [[CGDaemonClient shared] fetchConfigWithCompletion:^(CGConfig *config, NSError *error) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (strongSelf == nil) {
            return;
        }
        if (config == nil) {
            strongSelf->_offlineLabel.text = @"守护进程离线：开关未读取到配置，暂不可改动。";
            return;
        }
        strongSelf->_offlineLabel.hidden = YES;
        strongSelf->_enableSwitch.enabled = YES;
        strongSelf->_tempSwitch.enabled = YES;
        strongSelf->_smartSwitch.enabled = YES;
        strongSelf->_enableSwitch.on = config.enabled;
        strongSelf->_tempSwitch.on = config.tempEnabled;
        // Overnight fix: the switch must read/write adv_predictive_inhibit_charge,
        // not use_smart (runtime detection, daemon ignores set_conf use_smart).
        strongSelf->_smartSwitch.on = config.predictiveInhibitEnabled;
    }];
}

- (void)switchChanged:(UISwitch *)sender {
    NSString *key = nil;
    if (sender.tag == 1) {
        key = @"enable";
    } else if (sender.tag == 2) {
        key = @"enable_temp";
    } else if (sender.tag == 3) {
        key = @"adv_predictive_inhibit_charge";
    }
    if (key == nil) {
        return;
    }
    BOOL newValue = sender.on;
    __weak typeof(self) weakSelf = self;
    [[CGDaemonClient shared] setConfigValue:@(newValue) forKey:key completion:^(BOOL success, NSError *error) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (strongSelf == nil) {
            return;
        }
        if (!success) {
            sender.on = !newValue; // rollback on failure
        }
    }];
}

- (void)cgGoBack {
    [self.navigationController popViewControllerAnimated:YES];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    // A12: returning from a legacy page must re-hide the nav bar (it was
    // unhidden so the legacy page has a visible back button).
    self.navigationController.navigationBarHidden = YES;
}

- (void)openLegacyAdvanced {
    // A12: legacy pages have no in-content back button and the root hides
    // the nav bar, so without this they are only escapable by edge-swipe.
    self.navigationController.navigationBarHidden = NO;
    [self.navigationController pushViewController:[[CLAdvancedSettingsViewController alloc] init] animated:YES];
}

@end

#pragma mark - Software

@implementation CGSoftwareViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor systemBackgroundColor];
    self.title = @"软件设置";
    UIStackView *stack = CGVerticalStack(@[]);
    NSString *version = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleShortVersionString"] ?: @"?";
    [stack addArrangedSubview:CGBackButton(self, @selector(cgGoBack))];
    [stack addArrangedSubview:CGCardLabel(@"软件设置 · 新版", 24, UIFontWeightBold, [UIColor labelColor])];
    [stack addArrangedSubview:CGCardWithStack(CGVerticalStack(@[
        CGCardLabel([NSString stringWithFormat:@"ChargeGuard %@", version], 20, UIFontWeightBold, [UIColor labelColor]),
        CGCardLabel(@"基于 lich4/ChargeLimiter（原版）与 tunecc/ChargeLimiter（分支）更新维护，由 xstar68/ChargeGuard 继续维护。帮助页只保留一个项目链接：xstar68 的项目地址。", 14, UIFontWeightRegular, [UIColor secondaryLabelColor]),
    ]))];
    [stack addArrangedSubview:CGTextButton(@"检查更新（打开 xstar68 发布页）", self, @selector(openReleases))];
    [stack addArrangedSubview:CGTextButton(@"导出诊断报告（可分享，不改配置）", self, @selector(exportDiagnostics))];
    [stack addArrangedSubview:CGTextButton(@"复制自动化链接：开始充电 cl:///charge", self, @selector(copyChargeURL))];
    [stack addArrangedSubview:CGTextButton(@"复制自动化链接：停止充电 cl:///nocharge", self, @selector(copyNoChargeURL))];
    [stack addArrangedSubview:CGTextButton(@"打开完整旧版软件设置页", self, @selector(openLegacySoftware))];
    CGAddScrollStack(self, stack);
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
        if (strongSelf == nil) {
            return;
        }
        if (config == nil) {
            UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"导出失败" message:@"未读取到配置，诊断报告无法生成。" preferredStyle:UIAlertControllerStyleAlert];
            [alert addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleDefault handler:nil]];
            [strongSelf presentViewController:alert animated:YES completion:nil];
            return;
        }
        [[CGDaemonClient shared] fetchDiagnosticsWithCompletion:^(NSDictionary *diag, NSError *diagError) {
            __strong typeof(weakSelf) strongSelf2 = weakSelf;
            if (strongSelf2 == nil) {
                return;
            }
            if (diagError != nil && diag == nil) {
                UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"导出失败" message:@"诊断数据读取失败，未生成空报告。" preferredStyle:UIAlertControllerStyleAlert];
                [alert addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleDefault handler:nil]];
                [strongSelf2 presentViewController:alert animated:YES completion:nil];
                return;
            }
            // A13: previously battery:@{} always, so the report always said
            // "未读取到电池数据" even though battery info was available.
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
                                                                analyticsSummary:@"由历史分析页生成（见历史统计）。本导出本身不含历史明细，如需明细请在历史页查看。"
                                                                         appVersion:version];
            UIActivityViewController *share = [[UIActivityViewController alloc] initWithActivityItems:@[report] applicationActivities:nil];
            [strongSelf2 presentViewController:share animated:YES completion:nil];
        }];
    }];
}

- (void)copyChargeURL {
    [UIPasteboard generalPasteboard].string = [[CGPresetManager chargeURL] absoluteString];
}

- (void)copyNoChargeURL {
    [UIPasteboard generalPasteboard].string = [[CGPresetManager noChargeURL] absoluteString];
}

- (void)cgGoBack {
    [self.navigationController popViewControllerAnimated:YES];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    // A12: returning from a legacy page must re-hide the nav bar (it was
    // unhidden so the legacy page has a visible back button).
    self.navigationController.navigationBarHidden = YES;
}

- (void)openLegacySoftware {
    // A12: legacy pages have no in-content back button and the root hides
    // the nav bar, so without this they are only escapable by edge-swipe.
    self.navigationController.navigationBarHidden = NO;
    [self.navigationController pushViewController:[[CLSoftwareSettingsViewController alloc] init] animated:YES];
}

@end
