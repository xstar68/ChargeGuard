// CLChargeGuardPrefsController.m
// ChargeGuard Settings bundle controller (deb only, Theos build).
// NOT part of the Xcode app target: it must not be added to project.pbxproj,
// because Preferences.framework / Theos headers are not available in the app build.
// Interface contract (same as the app, verified in CLAPIClient.m):
//   POST http://127.0.0.1:1230/  JSON {api: "get_conf"}  -> {status: 0, data: {...}}
//   POST http://127.0.0.1:1230/  JSON {api: "set_conf", key: <key>, val: <value>}
// Keys (meanings unchanged from v1.17.6): enable, charge_above (15-100, default 80),
// charge_below (10-95, default 20), enable_temp, charge_temp_above (30-50, default 40),
// charge_temp_below (25-49, default 35).
// This controller deliberately never writes NSUserDefaults as config: the daemon
// reads its KV store (CLSettingsStore), not a defaults domain, so a defaults write
// would look saved in Settings while the daemon keeps the old value.
// Offline behaviour: no switch or slider is shown until a confirmed get_conf
// returns, so Settings never presents the 80/20/40/35 defaults as if they
// were daemon values.
#import <Preferences/PSListController.h>
#import <Preferences/PSSpecifier.h>

@interface CLChargeGuardPrefsController : PSListController
@end

@implementation CLChargeGuardPrefsController {
    NSDictionary *_config;
    BOOL _loading;
    BOOL _offline;
}

- (NSArray *)specifiers {
    if (_specifiers) return _specifiers;
    if (_loading) {
        PSSpecifier *group = [PSSpecifier groupSpecifierWithName:@"ChargeGuard"];
        [group setProperty:@"正在读取守护进程配置…" forKey:@"footerText"];
        // 2026-11-01 构建 #9 真因：PSListController 的 _specifiers 是
        // NSMutableArray *，@[group] 是 NSArray *，Theos 用 -Werror 编译
        // 时直接报错。之前打包脚本把 Theos 输出静默丢弃了，这个错一直
        // 被藏着，只留下一个没有二进制的空 bundle；现在校验放开才暴露。
        _specifiers = [NSMutableArray arrayWithObject:group];
        return _specifiers;
    }
    if (_offline || _config == nil) {
        PSSpecifier *group = [PSSpecifier groupSpecifierWithName:@"ChargeGuard"];
        [group setProperty:@"守护进程离线：未读取到配置，未显示任何数值。守护进程恢复后重新打开本页即可。" forKey:@"footerText"];
        _specifiers = [NSMutableArray arrayWithObject:group];
        return _specifiers;
    }
    NSMutableArray *specifiers = [NSMutableArray array];
    PSSpecifier *chargeGroup = [PSSpecifier groupSpecifierWithName:@"充电控制"];
    [chargeGroup setProperty:@"停充阈值与开始充电阈值。改动立即写守护进程，失败时自动回滚显示值。" forKey:@"footerText"];
    [specifiers addObject:chargeGroup];
    [specifiers addObject:[self switchSpecifierWithTitle:@"完整控制" key:@"enable"]];
    [specifiers addObject:[self sliderSpecifierWithTitle:@"停止充电 ≥" key:@"charge_above" min:15 max:100]];
    [specifiers addObject:[self sliderSpecifierWithTitle:@"开始充电 ≤" key:@"charge_below" min:10 max:95]];
    PSSpecifier *tempGroup = [PSSpecifier groupSpecifierWithName:@"温度"];
    [tempGroup setProperty:@"高温停充与降温恢复阈值。" forKey:@"footerText"];
    [specifiers addObject:tempGroup];
    [specifiers addObject:[self switchSpecifierWithTitle:@"高温停充" key:@"enable_temp"]];
    [specifiers addObject:[self sliderSpecifierWithTitle:@"高温停充 ≥" key:@"charge_temp_above" min:30 max:50]];
    [specifiers addObject:[self sliderSpecifierWithTitle:@"降温恢复 ≤" key:@"charge_temp_below" min:25 max:49]];
    _specifiers = [specifiers copy];
    return _specifiers;
}

- (PSSpecifier *)switchSpecifierWithTitle:(NSString *)title key:(NSString *)key {
    PSSpecifier *specifier = [PSSpecifier preferenceSpecifierNamed:title
                                                           target:self
                                                              set:@selector(setPreferenceValue:specifier:)
                                                              get:@selector(readPreferenceValue:)
                                                           detail:Nil
                                                             cell:PSSwitchCell
                                                             edit:Nil];
    [specifier setProperty:key forKey:@"key"];
    return specifier;
}

- (PSSpecifier *)sliderSpecifierWithTitle:(NSString *)title key:(NSString *)key min:(NSInteger)min max:(NSInteger)max {
    PSSpecifier *specifier = [PSSpecifier preferenceSpecifierNamed:title
                                                           target:self
                                                              set:@selector(setPreferenceValue:specifier:)
                                                              get:@selector(readPreferenceValue:)
                                                           detail:Nil
                                                             cell:PSSliderCell
                                                             edit:Nil];
    [specifier setProperty:key forKey:@"key"];
    [specifier setProperty:@(min) forKey:@"min"];
    [specifier setProperty:@(max) forKey:@"max"];
    return specifier;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    _loading = YES;
    _offline = NO;
    [self refreshFromDaemon];
}

- (void)refreshFromDaemon {
    NSURL *url = [NSURL URLWithString:@"http://127.0.0.1:1230/"];
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    request.HTTPMethod = @"POST";
    [request setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
    request.HTTPBody = [NSJSONSerialization dataWithJSONObject:@{@"api": @"get_conf"} options:0 error:nil];
    NSURLSessionDataTask *task = [[NSURLSession sharedSession] dataTaskWithRequest:request
        completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
            dispatch_async(dispatch_get_main_queue(), ^{
                self->_loading = NO;
                NSDictionary *json = nil;
                if (data != nil) {
                    json = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
                }
                NSDictionary *config = json[@"data"];
                if ([json[@"status"] intValue] == 0 && [config isKindOfClass:[NSDictionary class]]) {
                    self->_config = config;
                    self->_offline = NO;
                } else {
                    self->_config = nil;
                    self->_offline = YES;
                }
                [self reloadSpecifiers];
            });
        }];
    [task resume];
}

- (id)readPreferenceValue:(PSSpecifier *)specifier {
    NSString *key = [specifier propertyForKey:@"key"];
    id value = _config[key];
    if (value != nil) {
        return value;
    }
    // Fallbacks match daemon defaults, used only if a key is absent from
    // an otherwise confirmed config (never as a substitute for get_conf).
    static NSDictionary *defaults = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        defaults = @{@"enable": @YES, @"charge_above": @80, @"charge_below": @20,
                     @"enable_temp": @YES, @"charge_temp_above": @40, @"charge_temp_below": @35};
    });
    return defaults[key] ?: @0;
}

- (void)setPreferenceValue:(id)value specifier:(PSSpecifier *)specifier {
    NSString *key = [specifier propertyForKey:@"key"];
    if (key == nil || _offline) {
        [self reloadSpecifiers]; // rollback: offline writes are not shown as applied
        return;
    }
    // Range gate (same ranges as the app sliders); out-of-range writes
    // are rejected locally and never reach the daemon.
    static NSDictionary *ranges = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        ranges = @{@"charge_above": @[@15, @100], @"charge_below": @[@10, @95],
                   @"charge_temp_above": @[@30, @50], @"charge_temp_below": @[@25, @49]};
    });
    NSArray *range = ranges[key];
    if (range != nil) {
        NSInteger v = [value integerValue];
        if (v < [range[0] integerValue] || v > [range[1] integerValue]) {
            [self reloadSpecifiers];
            return;
        }
    }
    // Overnight fix: cross-check the pairs, mirroring CGConfig/app clamps.
    // The daemon does not validate them, so Settings alone could otherwise
    // persist tempBelow >= tempAbove (or chargeBelow >= chargeAbove) and
    // leave the stop/resume bands overlapping. _config holds the last
    // confirmed get_conf values; fall back to defaults for missing keys.
    if ([key isEqualToString:@"charge_temp_below"]) {
        NSInteger other = [_config[@"charge_temp_above"] integerValue] ?: 40;
        if ([value integerValue] >= other) { [self reloadSpecifiers]; return; }
    } else if ([key isEqualToString:@"charge_temp_above"]) {
        NSInteger other = [_config[@"charge_temp_below"] integerValue] ?: 35;
        if ([value integerValue] <= other) { [self reloadSpecifiers]; return; }
    } else if ([key isEqualToString:@"charge_below"]) {
        NSInteger other = [_config[@"charge_above"] integerValue] ?: 80;
        if ([value integerValue] >= other) { [self reloadSpecifiers]; return; }
    } else if ([key isEqualToString:@"charge_above"]) {
        NSInteger other = [_config[@"charge_below"] integerValue] ?: 20;
        if ([value integerValue] <= other) { [self reloadSpecifiers]; return; }
    }
    id previous = _config[key];
    NSMutableDictionary *next = [_config mutableCopy] ?: [NSMutableDictionary dictionary];
    next[key] = value;
    _config = [next copy];
    NSURL *url = [NSURL URLWithString:@"http://127.0.0.1:1230/"];
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    request.HTTPMethod = @"POST";
    [request setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
    request.HTTPBody = [NSJSONSerialization dataWithJSONObject:@{@"api": @"set_conf", @"key": key, @"val": value} options:0 error:nil];
    NSURLSessionDataTask *task = [[NSURLSession sharedSession] dataTaskWithRequest:request
        completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
            dispatch_async(dispatch_get_main_queue(), ^{
                NSDictionary *json = nil;
                if (data != nil) {
                    json = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
                }
                if (error != nil || [json[@"status"] intValue] != 0) {
                    // Roll back the display value on failure.
                    NSMutableDictionary *rolledBack = [self->_config mutableCopy];
                    if (previous != nil) {
                        rolledBack[key] = previous;
                    } else {
                        [rolledBack removeObjectForKey:key];
                    }
                    self->_config = [rolledBack copy];
                    [self reloadSpecifiers];
                }
            });
        }];
    [task resume];
}

@end
