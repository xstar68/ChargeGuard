//
//  CGHistoryAnalytics.h
//  ChargeGuard v3.0 — charge-history analytics (new feature, read-only)
//
//  Pure logic over the daemon's existing history buckets (min5/hour/day/
//  month arrays of dictionaries with CurrentCapacity, Temperature,
//  InstantAmperage/Amperage, Voltage, NominalChargeCapacity, CycleCount).
//  It invents no hardware data: every number comes from those records.
//  It never writes config and never changes stop-charge behaviour; its
//  outputs are display strings and suggestions only.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface CGHistoryAnalytics : NSObject

// Average charge rate (% per hour) over charging samples, 0 when unknown.
+ (double)averageChargeRatePercentPerHourFromSamples:(NSArray<NSDictionary *> *)samples;
+ (double)averageChargeRatePercentPerHourFromSamples:(NSArray<NSDictionary *> *)samples bucketMinutes:(NSInteger)bucketMinutes;
// Longest continuous charging span in minutes, 0 when unknown.
+ (NSInteger)longestChargingSpanMinutesFromSamples:(NSArray<NSDictionary *> *)samples;
+ (NSInteger)longestChargingSpanMinutesFromSamples:(NSArray<NSDictionary *> *)samples bucketMinutes:(NSInteger)bucketMinutes;
// Full-charge schedule suggestion: the latest time to start charging so
// the device reaches the stop threshold by wakeTime, given the measured
// rate. Returns nil when the rate is unknown.
+ (nullable NSString *)suggestedChargeStartForWakeHour:(NSInteger)wakeHour
                                              wakeMinute:(NSInteger)wakeMinute
                                       stopThresholdPercent:(NSInteger)stopPercent
                                          currentPercent:(NSInteger)currentPercent
                                  chargeRatePercentPerHour:(double)rate;
// Health alert: nil when health is healthy/unknown, otherwise a plain string.
+ (nullable NSString *)healthAlertForHealthPercent:(NSInteger)healthPercent
                                        cycleCount:(NSInteger)cycleCount
                                  nominalCapacitymAh:(NSInteger)nominal
                                   designCapacitymAh:(NSInteger)design;
// Cycle forecast: months until cycle count reaches 1000 at the observed
// monthly cycle rate; -1 when it cannot be computed.
+ (NSInteger)monthsUntilCycle1000FromMonthlyCycleCounts:(NSArray<NSNumber *> *)monthlyCounts
                                          currentCycles:(NSInteger)currentCycles;
// Temperature summary: max temperature and how many samples exceeded limit.
+ (NSDictionary *)temperatureSummaryFromSamples:(NSArray<NSDictionary *> *)samples
                                   highTempLimit:(double)limit;

@end

NS_ASSUME_NONNULL_END
