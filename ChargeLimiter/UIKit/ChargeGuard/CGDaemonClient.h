//
//  CGDaemonClient.h
//  ChargeGuard v3.0 — daemon client / API layer (new layered architecture)
//
//  The ONLY interface views and view models use to talk to the daemon.
//  It wraps the existing CLAPIClient transport (HTTP to 127.0.0.1:1230,
//  get_conf/set_conf/get_statistics/get_diag/...) and converts raw
//  dictionaries into CGConfig. It adds no new daemon protocol and changes
//  no stop-charge behaviour. All writes go through one gated method,
//  -applyConfig:, which validates with CGConfig first and refuses to
//  write an invalid config. Read-only features (analytics, export)
//  use only the fetch methods and can never write by themselves.
//

#import <Foundation/Foundation.h>

@class CGConfig;

NS_ASSUME_NONNULL_BEGIN

typedef void (^CGConfigCallback)(CGConfig *_Nullable config, NSError *_Nullable error);
typedef void (^CGDictionaryCallback)(NSDictionary *_Nullable response, NSError *_Nullable error);
typedef void (^CGVoidCallback)(BOOL success, NSError *_Nullable error);

@interface CGDaemonClient : NSObject

+ (instancetype)shared;

// Reads (never write).
- (void)fetchConfigWithCompletion:(CGConfigCallback)completion;
- (void)fetchBatteryInfoWithCompletion:(CGDictionaryCallback)completion;
- (void)fetchStatisticsWithCompletion:(CGDictionaryCallback)completion;
- (void)fetchDiagnosticsWithCompletion:(CGDictionaryCallback)completion;
- (void)fetchPolicyEventsWithLimit:(NSInteger)limit completion:(CGDictionaryCallback)completion;

// The single gated write path. Validates first; invalid configs are
// rejected locally and never reach the daemon.
// Writes are sequential (not parallel): if a key fails, writing stops and,
// when a previous config is supplied, its keys are written back best-effort
// so the daemon is not left half-updated while the UI reports "unchanged".
- (void)applyConfig:(CGConfig *)config completion:(CGVoidCallback)completion;
- (void)applyConfig:(CGConfig *)config previousConfig:(CGConfig *_Nullable)previous completion:(CGVoidCallback)completion;
// Single-key write, also validated when the key is a known threshold key.
- (void)setConfigValue:(id)value forKey:(NSString *)key completion:(CGVoidCallback)completion;

// Deep-redo additions (2026-11-01): the new sub-pages must be complete
// in-page, so the client also exposes the four daemon operations the old
// advanced/compat pages used. All four go through the same CLAPIClient
// transport; none adds a daemon protocol or changes stop-charge behaviour.
// Probe: tries several stop-charge writes, observes, then restores.
- (void)runChargeControlProbeWithWaitMs:(NSInteger)waitMs
                               restore:(BOOL)restore
                            completion:(CGDictionaryCallback)completion;
// Charging-thermal level: enabled + mode are submitted together, exactly
// as the old advanced page did (off = limit disabled, falls back to idle).
- (void)setLimitInflowEnabled:(BOOL)enabled
                         mode:(NSString *)mode
                   completion:(CGVoidCallback)completion;
// Restores system optimised charging; success is judged by the caller
// from the returned after_status, mirroring the old advanced page.
- (void)restoreSmartChargeWithCompletion:(CGDictionaryCallback)completion;
// Resets all daemon config; the caller re-reads config afterwards.
- (void)resetConfigWithCompletion:(CGVoidCallback)completion;

@end

NS_ASSUME_NONNULL_END
