//
//  CGHistoryAnalytics.m
//  ChargeGuard v3.0 — analytics implementation (read-only).
//

#import "CGHistoryAnalytics.h"

@implementation CGHistoryAnalytics

+ (double)averageChargeRatePercentPerHourFromSamples:(NSArray<NSDictionary *> *)samples {
    return [self averageChargeRatePercentPerHourFromSamples:samples bucketMinutes:5];
}

+ (double)averageChargeRatePercentPerHourFromSamples:(NSArray<NSDictionary *> *)samples bucketMinutes:(NSInteger)bucketMinutes {
    if (samples.count < 2 || bucketMinutes <= 0) {
        return 0;
    }
    // Samples are chronological. Rate = total percent gain while charging
    // divided by the number of 5-minute buckets that were charging.
    // Bucket length is not stored per record, so the min5 bucket (5 min)
    // is assumed only for the min5 series; callers pass min5 samples.
    double gain = 0;
    NSInteger chargingBuckets = 0;
    NSInteger previous = -1;
    for (NSDictionary *sample in samples) {
        NSInteger cap = [sample[@"CurrentCapacity"] integerValue];
        NSInteger amps = [sample[@"InstantAmperage"] integerValue];
        if (amps == 0) {
            amps = [sample[@"Amperage"] integerValue];
        }
        if (previous >= 0 && amps > 0 && cap > previous) {
            gain += (double)(cap - previous);
            chargingBuckets += 1;
        }
        previous = cap;
    }
    if (chargingBuckets == 0) {
        return 0;
    }
    // Buckets per hour depends on the series (min5: 12, hour: 1, day: 1/24, month: ~1/720).
    return (gain / (double)chargingBuckets) * (60.0 / (double)bucketMinutes);
}

+ (NSInteger)longestChargingSpanMinutesFromSamples:(NSArray<NSDictionary *> *)samples {
    return [self longestChargingSpanMinutesFromSamples:samples bucketMinutes:5];
}

+ (NSInteger)longestChargingSpanMinutesFromSamples:(NSArray<NSDictionary *> *)samples bucketMinutes:(NSInteger)bucketMinutes {
    NSInteger longest = 0;
    NSInteger current = 0;
    if (bucketMinutes <= 0) { bucketMinutes = 5; }
    for (NSDictionary *sample in samples) {
        NSInteger amps = [sample[@"InstantAmperage"] integerValue];
        if (amps == 0) {
            amps = [sample[@"Amperage"] integerValue];
        }
        if (amps > 0) {
            current += bucketMinutes;
            if (current > longest) {
                longest = current;
            }
        } else {
            current = 0;
        }
    }
    return longest;
}

+ (NSString *)suggestedChargeStartForWakeHour:(NSInteger)wakeHour
                                   wakeMinute:(NSInteger)wakeMinute
                        stopThresholdPercent:(NSInteger)stopPercent
                               currentPercent:(NSInteger)currentPercent
                       chargeRatePercentPerHour:(double)rate {
    if (rate <= 0 || stopPercent <= currentPercent) {
        return nil;
    }
    // Clamp wake time; wrap with modulo so a >24h charge need cannot
    // produce negative or >24h clock times.
    if (wakeHour < 0) { wakeHour = 0; } else if (wakeHour > 23) { wakeHour = 23; }
    if (wakeMinute < 0) { wakeMinute = 0; } else if (wakeMinute > 59) { wakeMinute = 59; }
    double hoursNeeded = (double)(stopPercent - currentPercent) / rate;
    NSInteger minutesNeeded = (NSInteger)ceil(hoursNeeded * 60.0);
    NSInteger wakeTotal = wakeHour * 60 + wakeMinute;
    NSInteger startTotal = (wakeTotal - minutesNeeded) % (24 * 60);
    if (startTotal < 0) { startTotal += 24 * 60; }
    return [NSString stringWithFormat:@"按当前充电速度约 %.0f%%/小时，从 %ld%% 充到 %ld%% 约需 %ld 分钟，建议 %02ld:%02ld 开始充电，起床时刚好到达停充值（仅建议，不会自动改配置）。",
            rate, (long)currentPercent, (long)stopPercent, (long)minutesNeeded,
            (long)(startTotal / 60), (long)(startTotal % 60)];
}

+ (NSString *)healthAlertForHealthPercent:(NSInteger)healthPercent
                               cycleCount:(NSInteger)cycleCount
                         nominalCapacitymAh:(NSInteger)nominal
                          designCapacitymAh:(NSInteger)design {
    if (healthPercent <= 0) {
        return nil;
    }
    if (healthPercent < 80) {
        return [NSString stringWithFormat:@"电池健康度 %ld%%（循环 %ld 次），已低于 80%%，建议关注更换；停充阈值本身不受影响。", (long)healthPercent, (long)cycleCount];
    }
    if (design > 0 && nominal > 0 && nominal < design) {
        // Informational only, not an alert: capacity below design is normal wear.
        return nil;
    }
    return nil;
}

+ (NSInteger)monthsUntilCycle1000FromMonthlyCycleCounts:(NSArray<NSNumber *> *)monthlyCounts
                                         currentCycles:(NSInteger)currentCycles {
    if (monthlyCounts.count == 0 || currentCycles >= 1000) {
        return -1;
    }
    double total = 0;
    for (NSNumber *count in monthlyCounts) {
        total += [count doubleValue];
    }
    double monthlyRate = total / (double)monthlyCounts.count;
    if (monthlyRate <= 0) {
        return -1;
    }
    return (NSInteger)ceil((1000.0 - (double)currentCycles) / monthlyRate);
}

+ (NSDictionary *)temperatureSummaryFromSamples:(NSArray<NSDictionary *> *)samples
                                  highTempLimit:(double)limit {
    double maxTemp = 0;
    NSInteger overCount = 0;
    for (NSDictionary *sample in samples) {
        // Old-UI normalization: daemon stores raw temperature in hundredths
        // (e.g. 2850 = 28.5C); without it the page would print ~2850C.
        double temp = [sample[@"Temperature"] doubleValue];
        if (temp > 200) { temp /= 100.0; }
        if (temp > maxTemp) {
            maxTemp = temp;
        }
        if (limit > 0 && temp >= limit) {
            overCount += 1;
        }
    }
    return @{@"maxTemperature": @(maxTemp), @"samplesOverLimit": @(overCount), @"sampleCount": @(samples.count)};
}

@end
