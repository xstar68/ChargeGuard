//
//  CGDaemonClient.m
//  ChargeGuard v3.0 — daemon client implementation.
//

#import "CGDaemonClient.h"
#import "CGConfig.h"
#import "../CLAPIClient.h"

@interface CGDaemonClient ()
- (void)writeSingleKey:(NSString *)key value:(id)value completion:(CGVoidCallback)completion;
- (void)writeKeys:(NSArray<NSString *> *)keys
          values:(NSDictionary *)dict
           index:(NSInteger)index
        previous:(CGConfig *)previous
         written:(NSMutableArray<NSString *> *)written
   originalError:(NSError *)originalError
      completion:(CGVoidCallback)completion;
@end

@implementation CGDaemonClient

+ (instancetype)shared {
    static CGDaemonClient *shared = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        shared = [[CGDaemonClient alloc] init];
    });
    return shared;
}

- (void)fetchConfigWithCompletion:(CGConfigCallback)completion {
    [[CLAPIClient shared] getConfigWithKey:nil completion:^(NSDictionary *response, NSError *error) {
        if (completion == nil) {
            return;
        }
        if (error != nil || response == nil) {
            completion(nil, error ?: [NSError errorWithDomain:@"com.chargeguard.client" code:1 userInfo:@{NSLocalizedDescriptionKey: @"daemon did not answer get_conf"}]);
            return;
        }
        if ([response[@"status"] intValue] != 0 && response[@"data"] == nil) {
            completion(nil, [NSError errorWithDomain:@"com.chargeguard.client" code:2 userInfo:@{NSLocalizedDescriptionKey: @"daemon rejected get_conf"}]);
            return;
        }
        CGConfig *config = [CGConfig configFromDaemonDictionary:response];
        // A17: a status-0 payload with no known config keys at all (e.g.
        // data={}) must not be treated as a confirmed read — the old code
        // then displayed 80/20/40/35 defaults as confirmed and the next
        // slider write pushed those invented defaults over real values.
        NSSet *knownKeys = [NSSet setWithArray:@[@"charge_above", @"charge_below", @"charge_temp_above", @"charge_temp_below", @"enable", @"enable_temp", @"adv_predictive_inhibit_charge"]];
        BOOL hasKnownKey = NO;
        for (NSString *key in config.rawDaemonDictionary) {
            if ([knownKeys containsObject:key]) { hasKnownKey = YES; break; }
        }
        if (!hasKnownKey) {
            completion(nil, [NSError errorWithDomain:@"com.chargeguard.client" code:7 userInfo:@{NSLocalizedDescriptionKey: @"daemon get_conf returned no known config keys"}]);
            return;
        }
        completion(config, nil);
    }];
}

- (void)fetchBatteryInfoWithCompletion:(CGDictionaryCallback)completion {
    [[CLAPIClient shared] getBatteryInfoWithCompletion:completion];
}

- (void)fetchStatisticsWithCompletion:(CGDictionaryCallback)completion {
    // Overnight fix: an empty conf requests NO buckets — the daemon only
    // fills tables named in conf, so the old code always got data={}.
    // Mirror the old UI's initial-load conf (bucket sizes in samples).
    NSDictionary *conf = @{
        @"min5": @{@"n": @300, @"last_id": @0},
        @"hour": @{@"n": @300, @"last_id": @0},
        @"day": @{@"n": @200, @"last_id": @0},
        @"month": @{@"n": @200, @"last_id": @0},
    };
    [[CLAPIClient shared] getStatisticsWithConf:conf completion:completion];
}

- (void)fetchDiagnosticsWithCompletion:(CGDictionaryCallback)completion {
    [[CLAPIClient shared] getDiagWithCompletion:completion];
}

- (void)fetchPolicyEventsWithLimit:(NSInteger)limit completion:(CGDictionaryCallback)completion {
    [[CLAPIClient shared] getPolicyEventsWithLimit:limit lastID:0 completion:completion];
}

- (void)applyConfig:(CGConfig *)config completion:(CGVoidCallback)completion {
    [self applyConfig:config previousConfig:nil completion:completion];
}

- (void)applyConfig:(CGConfig *)config previousConfig:(CGConfig *)previous completion:(CGVoidCallback)completion {
    // A16: nil config must fail with a real error, not completion(NO, nil)
    // (messaging nil isValidWithError: returns NO without setting an error).
    if (config == nil) {
        if (completion != nil) {
            completion(NO, [NSError errorWithDomain:@"com.chargeguard.client" code:4 userInfo:@{NSLocalizedDescriptionKey: @"no config to apply"}]);
        }
        return;
    }
    NSError *validationError = nil;
    if (![config isValidWithError:&validationError]) {
        if (completion != nil) {
            completion(NO, validationError);
        }
        return;
    }
    NSDictionary *dict = [config daemonDictionary];
    // A3: write only keys that actually changed vs previous (when known).
    // The old code rewrote all 7 keys on every single-field change, and
    // daemon set_conf branches run unconditional side effects
    // (resetHoldSessionState on charge_above, session clearing on enable),
    // so a temp-slider drag could reset hold/session state it never touched.
    NSDictionary *prevDict = [previous daemonDictionary];
    NSMutableArray<NSString *> *keys = [NSMutableArray array];
    for (NSString *key in [[dict allKeys] sortedArrayUsingSelector:@selector(compare:)]) {
        if (previous == nil || ![dict[key] isEqual:prevDict[key]]) {
            [keys addObject:key];
        }
    }
    if (keys.count == 0) {
        if (completion != nil) {
            completion(YES, nil);
        }
        return;
    }
    [self writeKeys:keys values:dict index:0 previous:previous written:[NSMutableArray array] originalError:nil completion:completion];
}

- (void)writeKeys:(NSArray<NSString *> *)keys
          values:(NSDictionary *)dict
           index:(NSInteger)index
        previous:(CGConfig *)previous
         written:(NSMutableArray<NSString *> *)written
   originalError:(NSError *)originalError
      completion:(CGVoidCallback)completion {
    if (index >= (NSInteger)keys.count) {
        if (completion != nil) {
            completion(YES, nil);
        }
        return;
    }
    NSString *key = keys[(NSUInteger)index];
    [[CLAPIClient shared] setConfigWithKey:key value:dict[key] completion:^(NSDictionary *response, NSError *error) {
        BOOL ok = (error == nil && (response == nil || [response[@"status"] intValue] == 0));
        if (ok) {
            [written addObject:key];
            [self writeKeys:keys values:dict index:index + 1 previous:previous written:written originalError:originalError completion:completion];
            return;
        }
        NSError *failure = error ?: [NSError errorWithDomain:@"com.chargeguard.client" code:3 userInfo:@{NSLocalizedDescriptionKey: @"daemon rejected set_conf"}];
        if (previous == nil) {
            if (completion != nil) {
                completion(NO, failure);
            }
            return;
        }
        // Roll back ONLY keys already written (not the whole previous dict),
        // and if rollback itself fails, say so honestly instead of
        // asserting restoration (A11).
        NSDictionary *prevDict = [previous daemonDictionary];
        NSMutableArray<NSString *> *rollbackKeys = [NSMutableArray array];
        for (NSString *writtenKey in written) {
            if (prevDict[writtenKey] != nil) {
                [rollbackKeys addObject:writtenKey];
            }
        }
        if (rollbackKeys.count == 0) {
            if (completion != nil) {
                completion(NO, failure);
            }
            return;
        }
        [self writeKeys:rollbackKeys values:prevDict index:0 previous:nil written:[NSMutableArray array] originalError:failure completion:^(BOOL rollbackSuccess, NSError *rollbackError) {
            (void)rollbackError;
            if (rollbackSuccess) {
                if (completion != nil) {
                    completion(NO, failure);
                }
            } else {
                NSError *honest = [NSError errorWithDomain:@"com.chargeguard.client" code:5 userInfo:@{NSLocalizedDescriptionKey: @"修改失败，且回滚未完全成功，请重新进入页面核对配置"}];
                if (completion != nil) {
                    completion(NO, honest);
                }
            }
        }];
    }];
}

- (void)setConfigValue:(id)value forKey:(NSString *)key completion:(CGVoidCallback)completion {
    // A15: nil key/value must fail cleanly, never crash building the
    // request dictionary or via setNilValueForKey: on a scalar property.
    if (key == nil || value == nil) {
        if (completion != nil) {
            completion(NO, [NSError errorWithDomain:@"com.chargeguard.client" code:6 userInfo:@{NSLocalizedDescriptionKey: @"missing key or value"}]);
        }
        return;
    }
    static NSDictionary *thresholdKeys = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        thresholdKeys = @{
            @"charge_above": @"stopChargeAbove",
            @"charge_below": @"startChargeBelow",
            @"charge_temp_above": @"tempAbove",
            @"charge_temp_below": @"tempBelow",
        };
    });
    NSString *property = thresholdKeys[key];
    if (property == nil) {
        [self writeSingleKey:key value:value completion:completion];
        return;
    }
    // A9: validate against the LIVE config, not defaults. Validating
    // against 80/20/40/35 both false-accepts (daemon stop=50, set
    // charge_below=60 passes 60<80 but violates start<stop) and
    // false-rejects (daemon stop=100, set charge_below=90 is valid live
    // but rejected by the 80 default). Fall back to defaults only if the
    // live fetch itself fails.
    [self fetchConfigWithCompletion:^(CGConfig *live, NSError *fetchError) {
        (void)fetchError;
        CGConfig *probe = live ? [live copy] : [CGConfig defaultConfig];
        [probe setValue:value forKey:property];
        NSError *validationError = nil;
        if (![probe isValidWithError:&validationError]) {
            if (completion != nil) {
                completion(NO, validationError);
            }
            return;
        }
        [self writeSingleKey:key value:value completion:completion];
    }];
}

- (void)runChargeControlProbeWithWaitMs:(NSInteger)waitMs
                               restore:(BOOL)restore
                            completion:(CGDictionaryCallback)completion {
    [[CLAPIClient shared] runChargeControlProbeWithWaitMs:waitMs restore:restore completion:completion];
}

- (void)setLimitInflowEnabled:(BOOL)enabled
                         mode:(NSString *)mode
                   completion:(CGVoidCallback)completion {
    [[CLAPIClient shared] setLimitInflowEnabled:enabled mode:(mode ?: @"off") completion:^(NSDictionary *response, NSError *error) {
        if (completion != nil) {
            BOOL ok = (error == nil && (response == nil || [response[@"status"] intValue] == 0));
            completion(ok, error);
        }
    }];
}

- (void)restoreSmartChargeWithCompletion:(CGDictionaryCallback)completion {
    [[CLAPIClient shared] restoreSmartChargeWithCompletion:completion];
}

- (void)resetConfigWithCompletion:(CGVoidCallback)completion {
    [[CLAPIClient shared] resetConfigWithCompletion:^(NSDictionary *response, NSError *error) {
        if (completion != nil) {
            BOOL ok = (error == nil && (response == nil || [response[@"status"] intValue] == 0));
            completion(ok, error);
        }
    }];
}

- (void)writeSingleKey:(NSString *)key value:(id)value completion:(CGVoidCallback)completion {
    [[CLAPIClient shared] setConfigWithKey:key value:value completion:^(NSDictionary *response, NSError *error) {
        if (completion != nil) {
            BOOL ok = (error == nil && (response == nil || [response[@"status"] intValue] == 0));
            completion(ok, error);
        }
    }];
}

@end
