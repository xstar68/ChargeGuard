//
//  CGBatteryViewModel.h
//  ChargeGuard v3.0 — battery view model (new layered architecture)
//
//  Pure derivation: battery dictionary + CGConfig in, display strings out.
//  No UIKit, no daemon calls, no writes. The hero, pills and stat grid
//  in CGMainViewController render exactly what this object computes, so
//  the same values can be unit-checked without a device.
//

#import <Foundation/Foundation.h>

@class CGConfig;

NS_ASSUME_NONNULL_BEGIN

@interface CGBatteryViewModel : NSObject

@property (nonatomic, assign, readonly) NSInteger percent;
@property (nonatomic, assign, readonly) BOOL isCharging;
@property (nonatomic, assign, readonly) BOOL externalConnected;
@property (nonatomic, assign, readonly) NSInteger currentMilliamps;
@property (nonatomic, assign, readonly) double voltage;
@property (nonatomic, assign, readonly) double temperatureCelsius;
@property (nonatomic, assign, readonly) NSInteger healthPercent;
@property (nonatomic, assign, readonly) NSInteger cycleCount;
@property (nonatomic, assign, readonly) NSInteger nominalCapacitymAh;
@property (nonatomic, assign, readonly) NSInteger designCapacitymAh;
@property (nonatomic, strong, readonly, nullable) CGConfig *config;
@property (nonatomic, assign, readonly) BOOL daemonOnline;

- (instancetype)initWithBatteryDictionary:(nullable NSDictionary *)battery
                                  config:(nullable CGConfig *)config
                           daemonOnline:(BOOL)daemonOnline;

- (NSString *)heroPercentText;      // e.g. "83%"
- (NSString *)heroStatusText;       // e.g. "正在充电 · 已停充" derived from state
- (NSString *)heroModePillText;     // e.g. "完整控制 · 停充 ≥80%"
- (NSString *)heroAdapterPillText;  // e.g. "15W · PD" when wattage is known, else "—"
- (NSArray<NSDictionary *> *)statGridItems; // 2-column grid: title/value/subtitle
- (NSString *)temperatureAlertText; // nil when temperature is in range

@end

NS_ASSUME_NONNULL_END
