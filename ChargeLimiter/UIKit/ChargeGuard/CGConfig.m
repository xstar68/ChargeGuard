//
//  CGConfig.m
//  ChargeGuard v3.0 — configuration model implementation.
//

#import "CGConfig.h"

static NSInteger CGIntegerFromValue(id value, NSInteger fallback) {
    if ([value respondsToSelector:@selector(integerValue)]) {
        return [value integerValue];
    }
    return fallback;
}

static BOOL CGBoolFromValue(id value, BOOL fallback) {
    if (value == nil) {
        return fallback;
    }
    if ([value respondsToSelector:@selector(boolValue)]) {
        return [value boolValue];
    }
    return fallback;
}

@implementation CGConfig

+ (instancetype)defaultConfig {
    CGConfig *config = [[CGConfig alloc] init];
    config.stopChargeAbove = 80;
    config.startChargeBelow = 20;
    config.tempAbove = 40;
    config.tempBelow = 35;
    config.enabled = YES;
    config.tempEnabled = YES;
    config.smartStopEnabled = NO;
    config.predictiveInhibitEnabled = YES;
    return config;
}

+ (instancetype)configFromDaemonDictionary:(NSDictionary *)dict {
    CGConfig *config = [CGConfig defaultConfig];
    if (dict == nil) {
        return config;
    }
    // get_conf answers either as the config dict itself or under "data".
    NSDictionary *source = dict;
    id nested = dict[@"data"];
    if ([nested isKindOfClass:[NSDictionary class]]) {
        source = nested;
    }
    config.rawDaemonDictionary = source;
    config.stopChargeAbove = CGIntegerFromValue(source[@"charge_above"], config.stopChargeAbove);
    config.startChargeBelow = CGIntegerFromValue(source[@"charge_below"], config.startChargeBelow);
    config.tempAbove = CGIntegerFromValue(source[@"charge_temp_above"], config.tempAbove);
    config.tempBelow = CGIntegerFromValue(source[@"charge_temp_below"], config.tempBelow);
    config.enabled = CGBoolFromValue(source[@"enable"], config.enabled);
    config.tempEnabled = CGBoolFromValue(source[@"enable_temp"], config.tempEnabled);
    config.smartStopEnabled = CGBoolFromValue(source[@"use_smart"], config.smartStopEnabled);
    config.predictiveInhibitEnabled = CGBoolFromValue(source[@"adv_predictive_inhibit_charge"], config.predictiveInhibitEnabled);
    return config;
}

- (BOOL)isValidWithError:(NSError **)error {
    NSString *reason = nil;
    if (self.stopChargeAbove < 15 || self.stopChargeAbove > 100) {
        reason = @"stopChargeAbove out of range 15-100";
    } else if (self.startChargeBelow < 10 || self.startChargeBelow > 95) {
        reason = @"startChargeBelow out of range 10-95";
    } else if (self.startChargeBelow >= self.stopChargeAbove) {
        reason = @"startChargeBelow must be below stopChargeAbove";
    } else if (self.tempAbove < 30 || self.tempAbove > 50) {
        reason = @"tempAbove out of range 30-50";
    } else if (self.tempBelow < 25 || self.tempBelow > 49) {
        reason = @"tempBelow out of range 25-49";
    } else if (self.tempBelow >= self.tempAbove) {
        reason = @"tempBelow must be below tempAbove";
    }
    if (reason != nil) {
        if (error != NULL) {
            *error = [NSError errorWithDomain:@"com.chargeguard.config"
                                         code:100
                                     userInfo:@{NSLocalizedDescriptionKey: reason}];
        }
        return NO;
    }
    return YES;
}

- (NSDictionary *)daemonDictionary {
    // Overnight correction: use_smart is NOT a setting — it is the daemon's
    // runtime service detection, and set_conf use_smart is silently ignored
    // by the daemon. Writing it back was harmless but wrong; the real
    // smart-stop toggle is adv_predictive_inhibit_charge, written here.
    return @{
        @"charge_above": @(self.stopChargeAbove),
        @"charge_below": @(self.startChargeBelow),
        @"charge_temp_above": @(self.tempAbove),
        @"charge_temp_below": @(self.tempBelow),
        @"enable": @(self.enabled),
        @"enable_temp": @(self.tempEnabled),
        @"adv_predictive_inhibit_charge": @(self.predictiveInhibitEnabled),
    };
}

- (id)copyWithZone:(NSZone *)zone {
    CGConfig *copy = [[[self class] allocWithZone:zone] init];
    copy.stopChargeAbove = self.stopChargeAbove;
    copy.startChargeBelow = self.startChargeBelow;
    copy.tempAbove = self.tempAbove;
    copy.tempBelow = self.tempBelow;
    copy.enabled = self.enabled;
    copy.tempEnabled = self.tempEnabled;
    copy.smartStopEnabled = self.smartStopEnabled;
    copy.predictiveInhibitEnabled = self.predictiveInhibitEnabled;
    copy.rawDaemonDictionary = self.rawDaemonDictionary;
    return copy;
}

@end
