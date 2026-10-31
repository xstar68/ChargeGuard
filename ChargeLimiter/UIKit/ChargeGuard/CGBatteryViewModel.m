//
//  CGBatteryViewModel.m
//  ChargeGuard v3.0 — battery view model implementation.
//

#import "CGBatteryViewModel.h"
#import "CGConfig.h"

@implementation CGBatteryViewModel

- (instancetype)initWithBatteryDictionary:(NSDictionary *)battery
                                  config:(CGConfig *)config
                           daemonOnline:(BOOL)daemonOnline {
    self = [super init];
    if (self != nil) {
        NSDictionary *source = battery ?: @{};
        // CLBatteryManager-style keys first, daemon raw keys as fallback.
        id percent = source[@"CurrentCapacity"] ?: source[@"currentCapacity"] ?: source[@"percent"];
        _percent = [percent respondsToSelector:@selector(integerValue)] ? [percent integerValue] : 0;
        id charging = source[@"IsCharging"] ?: source[@"isCharging"] ?: source[@"charging"];
        _isCharging = [charging respondsToSelector:@selector(boolValue)] ? [charging boolValue] : NO;
        id external = source[@"ExternalConnected"] ?: source[@"externalConnected"];
        _externalConnected = [external respondsToSelector:@selector(boolValue)] ? [external boolValue] : NO;
        id current = source[@"InstantAmperage"] ?: source[@"Amperage"] ?: source[@"IncomingCurrent"] ?: source[@"current"];
        _currentMilliamps = [current respondsToSelector:@selector(integerValue)] ? [current integerValue] : 0;
        id voltage = source[@"Voltage"] ?: source[@"IncomingVoltage"] ?: source[@"voltage"];
        _voltage = [voltage respondsToSelector:@selector(doubleValue)] ? [voltage doubleValue] : 0;
        id temp = source[@"Temperature"] ?: source[@"temperature"];
        _temperatureCelsius = [temp respondsToSelector:@selector(doubleValue)] ? [temp doubleValue] : 0;
        id health = source[@"Health"] ?: source[@"health"];
        if (health == nil) {
            NSInteger nominal = [source[@"NominalChargeCapacity"] integerValue];
            NSInteger design = [source[@"DesignCapacity"] integerValue];
            _healthPercent = (design > 0) ? (NSInteger)llround((double)nominal * 100.0 / (double)design) : 0;
        } else {
            _healthPercent = [health integerValue];
        }
        _cycleCount = [source[@"CycleCount"] integerValue];
        _nominalCapacitymAh = [source[@"NominalChargeCapacity"] integerValue];
        _designCapacitymAh = [source[@"DesignCapacity"] integerValue];
        _config = [config copy]; // A20: copy, don't alias the caller's mutable config
        _daemonOnline = daemonOnline;
    }
    return self;
}

- (NSString *)heroPercentText {
    return [NSString stringWithFormat:@"%ld%%", (long)self.percent];
}

- (NSString *)heroStatusText {
    if (!self.daemonOnline) {
        return @"守护进程离线";
    }
    if (self.isCharging) {
        return @"正在充电";
    }
    // A8: the 120mA soft-stop inference is only valid while a charger is
    // connected; unplugged idle discharge (e.g. -50mA) is not "stopped".
    if (self.externalConnected && labs((long)self.currentMilliamps) <= 120) {
        return @"已停充";
    }
    return self.externalConnected ? @"未充电" : @"未连接电源";
}

- (NSString *)heroModePillText {
    if (self.config == nil) {
        return @"读取中…";
    }
    if (!self.config.enabled) {
        return @"已关闭";
    }
    return [NSString stringWithFormat:@"停充 ≥%ld%%", (long)self.config.stopChargeAbove];
}

- (NSString *)heroAdapterPillText {
    if (!self.externalConnected) {
        return @"—";
    }
    if (self.voltage > 0 && self.currentMilliamps != 0) {
        double watts = fabs(self.voltage * (double)self.currentMilliamps / 1000.0);
        return [NSString stringWithFormat:@"%.0fW", watts];
    }
    return @"—";
}

- (NSArray<NSDictionary *> *)statGridItems {
    return @[
        @{@"title": @"电流", @"value": [NSString stringWithFormat:@"%ld mA", (long)self.currentMilliamps], @"subtitle": self.isCharging ? @"正在充电" : @"未充电"},
        @{@"title": @"电压", @"value": [NSString stringWithFormat:@"%.2f V", self.voltage], @"subtitle": @"实时"},
        @{@"title": @"温度", @"value": [NSString stringWithFormat:@"%.1f℃", self.temperatureCelsius], @"subtitle": (self.config != nil && self.config.tempEnabled) ? [NSString stringWithFormat:@"高温停充 ≥%ld℃", (long)self.config.tempAbove] : @""},
        @{@"title": @"健康度", @"value": [NSString stringWithFormat:@"%ld%%", (long)self.healthPercent], @"subtitle": [NSString stringWithFormat:@"循环 %ld 次", (long)self.cycleCount]},
    ];
}

- (NSString *)temperatureAlertText {
    if (self.config == nil || !self.config.enabled || !self.config.tempEnabled) {
        return nil;
    }
    if (self.temperatureCelsius >= (double)self.config.tempAbove) {
        return [NSString stringWithFormat:@"温度已达 %.1f℃，高温停充已生效（≥%ld℃）。", self.temperatureCelsius, (long)self.config.tempAbove];
    }
    if (self.temperatureCelsius >= (double)self.config.tempAbove - 3.0 && self.temperatureCelsius > 0) {
        return [NSString stringWithFormat:@"温度 %.1f℃，接近高温停充阈值 %ld℃。", self.temperatureCelsius, (long)self.config.tempAbove];
    }
    return nil;
}

@end
