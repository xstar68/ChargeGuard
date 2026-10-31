//
//  CGConfig.h
//  ChargeGuard v3.0 — configuration model (new layered architecture)
//
//  The single place that knows daemon config keys, ranges and defaults.
//  Views and view models never build get_conf/set_conf dictionaries by hand;
//  they go through CGConfig + CGDaemonClient. This file changes NO daemon
//  behaviour: keys, ranges and defaults are the ones the daemon already uses.
//  Defaults (unchanged from v2.0): stop 80%, start 20%, high temp 40°C,
//  low temp 35°C. Ranges match the existing slider rows in the old UI
//  (stop 15–100, start 10–95, high temp 30–50, low temp 25–49).
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface CGConfig : NSObject <NSCopying>

@property (nonatomic, assign) NSInteger stopChargeAbove;   // charge_above, %
@property (nonatomic, assign) NSInteger startChargeBelow;  // charge_below, %
@property (nonatomic, assign) NSInteger tempAbove;         // charge_temp_above, °C
@property (nonatomic, assign) NSInteger tempBelow;         // charge_temp_below, °C
@property (nonatomic, assign) BOOL enabled;                // enable
@property (nonatomic, assign) BOOL tempEnabled;            // enable_temp
@property (nonatomic, assign) BOOL smartStopEnabled;       // use_smart: RUNTIME detection only (AppleSmartBattery vs IOPMPowerSource), never written back — the daemon ignores set_conf use_smart.
@property (nonatomic, assign) BOOL predictiveInhibitEnabled; // adv_predictive_inhibit_charge: the real smart-stop toggle (daemon default YES)
@property (nonatomic, strong, nullable) NSDictionary *rawDaemonDictionary;

+ (instancetype)defaultConfig;
+ (instancetype)configFromDaemonDictionary:(nullable NSDictionary *)dict;
- (BOOL)isValidWithError:(NSError **)error;
- (NSDictionary *)daemonDictionary;

@end

NS_ASSUME_NONNULL_END
