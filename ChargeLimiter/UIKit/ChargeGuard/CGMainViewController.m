//
//  CGMainViewController.m
//  ChargeGuard v3.0 — new main page implementation.
//  NOTE (overnight scope decision): the new CG pages' strings are currently
//  hardcoded Chinese; English locale will show Chinese on these pages only.
//  Old pages remain bilingual via CLL. Localising the CG layer is a
//  follow-up, not a silent assumption — see REPORT_V3_0.md section 九.

#import "CGMainViewController.h"
#import "CGConfig.h"
#import "CGDaemonClient.h"
#import "CGBatteryViewModel.h"
#import "CGPresetManager.h"
#import "CGDiagnosticsExporter.h"
#import "CGViews.h"
#import "CGSubPages.h"
#import "../CLBatteryManager.h"

// Legacy full pages (declared in their .m files, no public headers).
// Forward declarations let the new pages route to them without patching
// the legacy controllers.
@interface CLHistoryViewController : UIViewController
@end
@interface CLAdvancedSettingsViewController : UIViewController
@end
@interface CLHelpViewController : UIViewController
@end

@interface CGMainViewController ()
@property (nonatomic, strong) UIScrollView *scrollView;
@property (nonatomic, strong) UIStackView *stack;
@property (nonatomic, strong) UILabel *bannerLabel;
@property (nonatomic, strong) CGHeroView *heroView;
@property (nonatomic, strong) CGStatGridView *statGrid;
@property (nonatomic, strong) CGEntryGridView *entryGrid;
@property (nonatomic, strong) UILabel *alertLabel;
@property (nonatomic, strong) NSMutableDictionary<NSNumber *, UISlider *> *sliders;
@property (nonatomic, strong) NSMutableDictionary<NSNumber *, UILabel *> *sliderValueLabels;
@property (nonatomic, strong, nullable) CGConfig *config;
@property (nonatomic, assign) BOOL configConfirmed;
@property (nonatomic, strong, nullable) NSTimer *refreshTimer;
// A10: serialize config writes — a second gesture while a 7-key sequential
// write is in flight must not start from the stale base config, and a
// stale completion must not clobber a newer success.
@property (nonatomic, assign) BOOL writeInFlight;
@end

@implementation CGMainViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor systemBackgroundColor];
    self.sliders = [NSMutableDictionary dictionary];
    self.sliderValueLabels = [NSMutableDictionary dictionary];
    [self setupUI];
    [self refreshAll];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(batteryDidUpdate)
                                                 name:CLBatteryInfoDidUpdateNotification
                                               object:nil];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    // 2026-11-01 真机 bug：新主界面从未调用 startAutoRefresh，CLBatteryManager
    // 的电量/电流/电压/温度/健康/循环一直停在初始 0，主界面全是 0%，而配置
    // 是走 CGDaemonClient 直接读的，所以滑块 80/20/40/35 正常、电池数据全 0。
    // 旧主界面在 viewWillAppear 里调了 startAutoRefresh，新界面漏了这一行。
    [[CLBatteryManager shared] startAutoRefresh];
    // A7: refresh on return — otherwise a change made on a sub-page (e.g.
    // an advanced switch) stays stale on the main page for up to 60 s.
    [self refreshAll];
    [self.refreshTimer invalidate];
    self.refreshTimer = [NSTimer scheduledTimerWithTimeInterval:60.0
                                                         target:self
                                                       selector:@selector(refreshAll)
                                                       userInfo:nil
                                                        repeats:YES];
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    [self.refreshTimer invalidate];
    self.refreshTimer = nil;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [self.refreshTimer invalidate];
}

#pragma mark - UI

- (UILabel *)sectionTitle:(NSString *)text {
    UILabel *label = [[UILabel alloc] init];
    label.font = [UIFont systemFontOfSize:14 weight:UIFontWeightSemibold];
    label.textColor = [UIColor secondaryLabelColor];
    label.text = text;
    return label;
}

- (void)setupUI {
    self.scrollView = [[UIScrollView alloc] init];
    self.scrollView.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.scrollView];
    self.stack = [[UIStackView alloc] init];
    self.stack.axis = UILayoutConstraintAxisVertical;
    self.stack.spacing = 16;
    self.stack.translatesAutoresizingMaskIntoConstraints = NO;
    [self.scrollView addSubview:self.stack];
    [NSLayoutConstraint activateConstraints:@[
        [self.scrollView.topAnchor constraintEqualToAnchor:self.view.topAnchor],
        [self.scrollView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.scrollView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.scrollView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
        [self.stack.topAnchor constraintEqualToAnchor:self.scrollView.topAnchor constant:16],
        [self.stack.leadingAnchor constraintEqualToAnchor:self.scrollView.leadingAnchor constant:16],
        [self.stack.trailingAnchor constraintEqualToAnchor:self.scrollView.trailingAnchor constant:-16],
        [self.stack.bottomAnchor constraintEqualToAnchor:self.scrollView.bottomAnchor constant:-40],
        [self.stack.widthAnchor constraintEqualToAnchor:self.scrollView.widthAnchor constant:-32],
    ]];

    UILabel *title = [[UILabel alloc] init];
    title.font = [UIFont systemFontOfSize:28 weight:UIFontWeightBold];
    title.text = @"ChargeGuard";
    [self.stack addArrangedSubview:title];

    self.bannerLabel = [[UILabel alloc] init];
    self.bannerLabel.font = [UIFont systemFontOfSize:14 weight:UIFontWeightSemibold];
    self.bannerLabel.textAlignment = NSTextAlignmentCenter;
    self.bannerLabel.layer.cornerRadius = 10;
    self.bannerLabel.layer.masksToBounds = YES;
    self.bannerLabel.text = @"读取中…请稍候，正在从守护进程读取配置";
    self.bannerLabel.backgroundColor = [UIColor systemOrangeColor];
    self.bannerLabel.textColor = [UIColor whiteColor];
    [self.bannerLabel.heightAnchor constraintEqualToConstant:36].active = YES;
    [self.stack addArrangedSubview:self.bannerLabel];

    self.heroView = [[CGHeroView alloc] init];
    [self.heroView.heightAnchor constraintEqualToConstant:170].active = YES;
    [self.stack addArrangedSubview:self.heroView];

    [self.stack addArrangedSubview:[self sectionTitle:@"充电控制"]];
    [self.stack addArrangedSubview:[self controlCard]];

    [self.stack addArrangedSubview:[self sectionTitle:@"一键预设（点按即应用，仅改停充值）"]];
    [self.stack addArrangedSubview:[self presetCard]];

    [self.stack addArrangedSubview:[self sectionTitle:@"实时数据"]];
    self.statGrid = [[CGStatGridView alloc] init];
    [self.stack addArrangedSubview:self.statGrid];

    self.alertLabel = [[UILabel alloc] init];
    self.alertLabel.font = [UIFont systemFontOfSize:14];
    self.alertLabel.textColor = [UIColor systemOrangeColor];
    self.alertLabel.numberOfLines = 0;
    self.alertLabel.hidden = YES;
    [self.stack addArrangedSubview:self.alertLabel];

    // More Functions: 2-column large icon grid (v3, not a single-column list).
    [self.stack addArrangedSubview:[self sectionTitle:@"更多功能"]];
    self.entryGrid = [[CGEntryGridView alloc] init];
    __weak typeof(self) weakSelf = self;
    [self.entryGrid updateWithEntries:@[
        @{@"title": @"📊 历史统计", @"subtitle": @"趋势 · 满充建议 · 预测"},
        @{@"title": @"🧪 电池兼容性测试", @"subtitle": @"大结论卡 · 探针结果"},
        @{@"title": @"⚙️ 充电高级", @"subtitle": @"分组卡 · 右侧开关"},
        @{@"title": @"🔧 软件设置", @"subtitle": @"更新 · 诊断导出 · 自动化"},
    ] tapHandler:^(NSInteger index) {
        [weakSelf openEntryAtIndex:index];
    }];
    [self.stack addArrangedSubview:self.entryGrid];

    UIButton *helpButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [helpButton setTitle:@"帮助与来源（仅一个项目链接：xstar68/ChargeGuard）" forState:UIControlStateNormal];
    [helpButton addTarget:self action:@selector(openHelp) forControlEvents:UIControlEventTouchUpInside];
    [self.stack addArrangedSubview:helpButton];
}

- (UIView *)controlCard {
    UIView *card = [[UIView alloc] init];
    card.backgroundColor = [UIColor secondarySystemBackgroundColor];
    card.layer.cornerRadius = 16;
    UIStackView *stack = [[UIStackView alloc] init];
    stack.axis = UILayoutConstraintAxisVertical;
    stack.spacing = 12;
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    [card addSubview:stack];
    [NSLayoutConstraint activateConstraints:@[
        [stack.topAnchor constraintEqualToAnchor:card.topAnchor constant:16],
        [stack.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:16],
        [stack.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-16],
        [stack.bottomAnchor constraintEqualToAnchor:card.bottomAnchor constant:-16],
    ]];
    // Slider tags: 1 stop (15-100), 2 start (10-95), 3 high temp (30-50), 4 low temp (25-49).
    // Ranges, defaults and write-once-on-release semantics are unchanged from v2.0.
    [stack addArrangedSubview:[self sliderRowWithTag:1 title:@"停止充电 ≥" min:15 max:100 value:80 unit:@"%"]];
    [stack addArrangedSubview:[self sliderRowWithTag:2 title:@"开始充电 ≤" min:10 max:95 value:20 unit:@"%"]];
    [stack addArrangedSubview:[self sliderRowWithTag:3 title:@"高温停充 ≥" min:30 max:50 value:40 unit:@"℃"]];
    [stack addArrangedSubview:[self sliderRowWithTag:4 title:@"降温恢复 ≤" min:25 max:49 value:35 unit:@"℃"]];
    return card;
}

- (UIView *)sliderRowWithTag:(NSInteger)tag title:(NSString *)title min:(float)min max:(float)max value:(float)value unit:(NSString *)unit {
    UIStackView *row = [[UIStackView alloc] init];
    row.axis = UILayoutConstraintAxisHorizontal;
    row.spacing = 8;
    UILabel *titleLabel = [[UILabel alloc] init];
    titleLabel.font = [UIFont systemFontOfSize:16 weight:UIFontWeightSemibold];
    titleLabel.text = title;
    [titleLabel.widthAnchor constraintEqualToConstant:96].active = YES;
    UISlider *slider = [[UISlider alloc] init];
    slider.tag = tag;
    slider.minimumValue = min;
    slider.maximumValue = max;
    slider.value = value;
    slider.enabled = NO; // enabled only after the first confirmed config read
    [slider addTarget:self action:@selector(sliderChanged:) forControlEvents:UIControlEventValueChanged];
    [slider addTarget:self action:@selector(sliderEnded:) forControlEvents:UIControlEventTouchUpInside | UIControlEventTouchUpOutside | UIControlEventTouchCancel];
    UILabel *valueLabel = [[UILabel alloc] init];
    valueLabel.font = [UIFont systemFontOfSize:17 weight:UIFontWeightBold];
    valueLabel.text = [NSString stringWithFormat:@"%.0f%@", value, unit];
    [valueLabel.widthAnchor constraintEqualToConstant:56].active = YES;
    self.sliders[@(tag)] = slider;
    self.sliderValueLabels[@(tag)] = valueLabel;
    [row addArrangedSubview:titleLabel];
    [row addArrangedSubview:slider];
    [row addArrangedSubview:valueLabel];
    return row;
}

- (UIView *)presetCard {
    UIStackView *row = [[UIStackView alloc] init];
    row.axis = UILayoutConstraintAxisHorizontal;
    row.spacing = 10;
    row.distribution = UIStackViewDistributionFillEqually;
    for (CGPreset *preset in [CGPresetManager allPresets]) {
        UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
        button.backgroundColor = [UIColor secondarySystemBackgroundColor];
        button.layer.cornerRadius = 14;
        button.titleLabel.numberOfLines = 0;
        button.titleLabel.textAlignment = NSTextAlignmentCenter;
        [button setTitle:[NSString stringWithFormat:@"%@\n%@", preset.title, preset.subtitle] forState:UIControlStateNormal];
        button.titleLabel.font = [UIFont systemFontOfSize:14 weight:UIFontWeightSemibold];
        [button addTarget:self action:@selector(presetTapped:) forControlEvents:UIControlEventTouchUpInside];
        // Identify the preset by its stop value via the button tag offset.
        button.tag = 1000 + preset.stopChargeAbove;
        [button.heightAnchor constraintEqualToConstant:64].active = YES;
        [row addArrangedSubview:button];
    }
    return row;
}

#pragma mark - Data

- (NSDictionary *)batteryDictionaryFromManager {
    CLBatteryManager *manager = [CLBatteryManager shared];
    return @{
        @"CurrentCapacity": @(manager.currentCapacity),
        @"IsCharging": @(manager.isCharging),
        @"InstantAmperage": @(manager.instantAmperage),
        @"Amperage": @(manager.amperage),
        @"Voltage": @(manager.voltage),
        @"Temperature": @(manager.temperature),
        @"Health": @(manager.health),
        @"CycleCount": @(manager.cycleCount),
        @"NominalChargeCapacity": @(manager.nominalCapacity),
        @"DesignCapacity": @(manager.designCapacity),
        @"ExternalConnected": @(manager.externalConnected),
    };
}

- (void)refreshAll {
    __weak typeof(self) weakSelf = self;
    [[CGDaemonClient shared] fetchConfigWithCompletion:^(CGConfig *config, NSError *error) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (strongSelf == nil) {
            return;
        }
        if (config != nil) {
            strongSelf.config = config;
            strongSelf.configConfirmed = YES;
            strongSelf.bannerLabel.hidden = YES;
            [strongSelf applyConfigToSliders:config];
        } else {
            strongSelf.configConfirmed = NO;
            strongSelf.bannerLabel.hidden = NO;
            strongSelf.bannerLabel.text = @"守护进程离线：未读取到配置，当前数值不是已确认配置";
            strongSelf.bannerLabel.backgroundColor = [UIColor systemRedColor];
            for (UISlider *slider in strongSelf.sliders.allValues) {
                slider.enabled = NO;
            }
        }
        [strongSelf updateBatteryViews];
    }];
}

- (void)batteryDidUpdate {
    [self updateBatteryViews];
}

- (void)updateBatteryViews {
    // A17: when the last refresh failed, do not render the stale config
    // as if current — pass nil so the pill shows "读取中…" instead of an
    // old threshold presented as confirmed.
    CGBatteryViewModel *viewModel = [[CGBatteryViewModel alloc] initWithBatteryDictionary:[self batteryDictionaryFromManager]
                                                                                   config:(self.configConfirmed ? self.config : nil)
                                                                            daemonOnline:self.configConfirmed];
    [self.heroView updateWithPercentText:[viewModel heroPercentText]
                              statusText:[viewModel heroStatusText]
                           modePillText:[viewModel heroModePillText]
                        adapterPillText:[viewModel heroAdapterPillText]
                             isCharging:viewModel.isCharging];
    [self.statGrid updateWithItems:[viewModel statGridItems]];
    NSString *alert = [viewModel temperatureAlertText];
    if (alert == nil) {
        alert = [self healthAlertTextForViewModel:viewModel];
    }
    self.alertLabel.hidden = (alert == nil);
    self.alertLabel.text = alert ?: @"";
}

- (NSString *)healthAlertTextForViewModel:(CGBatteryViewModel *)viewModel {
    if (viewModel.healthPercent > 0 && viewModel.healthPercent < 80) {
        return [NSString stringWithFormat:@"电池健康度 %ld%%（循环 %ld 次），已低于 80%%，建议关注更换。", (long)viewModel.healthPercent, (long)viewModel.cycleCount];
    }
    return nil;
}

- (void)applyConfigToSliders:(CGConfig *)config {
    self.sliders[@(1)].value = (float)config.stopChargeAbove;
    self.sliders[@(2)].value = (float)config.startChargeBelow;
    self.sliders[@(3)].value = (float)config.tempAbove;
    self.sliders[@(4)].value = (float)config.tempBelow;
    self.sliderValueLabels[@(1)].text = [NSString stringWithFormat:@"%ld%%", (long)config.stopChargeAbove];
    self.sliderValueLabels[@(2)].text = [NSString stringWithFormat:@"%ld%%", (long)config.startChargeBelow];
    self.sliderValueLabels[@(3)].text = [NSString stringWithFormat:@"%ld℃", (long)config.tempAbove];
    self.sliderValueLabels[@(4)].text = [NSString stringWithFormat:@"%ld℃", (long)config.tempBelow];
    for (UISlider *slider in self.sliders.allValues) {
        slider.enabled = YES;
    }
}

#pragma mark - Actions

- (void)sliderChanged:(UISlider *)sender {
    // Live UI only; the daemon write happens once on release (v2.0 behaviour).
    NSString *unit = (sender.tag <= 2) ? @"%" : @"℃";
    self.sliderValueLabels[@(sender.tag)].text = [NSString stringWithFormat:@"%.0f%@", sender.value, unit];
}

- (void)sliderEnded:(UISlider *)sender {
    if (self.config == nil || self.writeInFlight) {
        return;
    }
    self.writeInFlight = YES;
    CGConfig *next = [self.config copy];
    NSInteger value = (NSInteger)lroundf(sender.value);
    if (sender.tag == 1) {
        next.stopChargeAbove = value;
    } else if (sender.tag == 2) {
        next.startChargeBelow = value;
    } else if (sender.tag == 3) {
        next.tempAbove = value;
    } else if (sender.tag == 4) {
        next.tempBelow = value;
    }
    __weak typeof(self) weakSelf = self;
    CGConfig *previous = self.config;
    [[CGDaemonClient shared] applyConfig:next previousConfig:previous completion:^(BOOL success, NSError *error) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (strongSelf == nil) {
            return;
        }
        strongSelf.writeInFlight = NO;
        if (success) {
            strongSelf.config = next;
        } else {
            // A10/A11: redraw from the CAPTURED previous, not the current
            // config (which a newer write may have changed), and show the
            // real failure reason — a local validation rejection is not a
            // daemon rejection, and a failed rollback must not be promised
            // as restored. Then re-fetch truth from the daemon.
            [strongSelf applyConfigToSliders:previous];
            NSString *message = error.localizedDescription.length > 0 ? error.localizedDescription : @"保存失败，请重新进入页面核对。";
            UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"保存失败"
                                                                           message:message
                                                                    preferredStyle:UIAlertControllerStyleAlert];
            [alert addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleDefault handler:nil]];
            [strongSelf presentViewController:alert animated:YES completion:nil];
            [strongSelf refreshAll];
        }
    }];
}

- (void)presetTapped:(UIButton *)sender {
    if (self.config == nil || self.writeInFlight) {
        return;
    }
    self.writeInFlight = YES;
    NSInteger stopValue = sender.tag - 1000;
    CGPreset *matched = nil;
    for (CGPreset *preset in [CGPresetManager allPresets]) {
        if (preset.stopChargeAbove == stopValue) {
            matched = preset;
            break;
        }
    }
    if (matched == nil) {
        return;
    }
    CGConfig *next = [CGPresetManager configByApplyingPreset:matched toBaseConfig:self.config];
    __weak typeof(self) weakSelf = self;
    CGConfig *previous = self.config;
    [[CGDaemonClient shared] applyConfig:next previousConfig:previous completion:^(BOOL success, NSError *error) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (strongSelf == nil) {
            return;
        }
        strongSelf.writeInFlight = NO;
        if (success) {
            strongSelf.config = next;
            [strongSelf applyConfigToSliders:next];
        } else {
            NSString *message = error.localizedDescription.length > 0 ? error.localizedDescription : @"预设未应用，配置未变。";
            UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"预设未应用"
                                                                           message:message
                                                                    preferredStyle:UIAlertControllerStyleAlert];
            [alert addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleDefault handler:nil]];
            [strongSelf presentViewController:alert animated:YES completion:nil];
            [strongSelf refreshAll];
        }
    }];
}

- (void)openEntryAtIndex:(NSInteger)index {
    UIViewController *target = nil;
    if (index == 0) {
        target = [[CGHistoryAnalyticsViewController alloc] init];
    } else if (index == 1) {
        target = [[CGCompatResultViewController alloc] init];
    } else if (index == 2) {
        target = [[CGAdvancedViewController alloc] init];
    } else if (index == 3) {
        target = [[CGSoftwareViewController alloc] init];
    }
    if (target != nil) {
        [self.navigationController pushViewController:target animated:YES];
    }
}

- (void)openHelp {
    CLHelpViewController *help = [[CLHelpViewController alloc] init];
    [self.navigationController pushViewController:help animated:YES];
}

@end
