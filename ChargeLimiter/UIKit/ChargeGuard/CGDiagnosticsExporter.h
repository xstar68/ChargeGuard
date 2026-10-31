//
//  CGDiagnosticsExporter.h
//  ChargeGuard v3.0 — exportable diagnostics report (new feature, read-only)
//
//  Builds a plain-text report from already-fetched data (config, battery,
//  diagnostics, analytics summary). It writes nothing to the daemon and
//  changes no setting. The caller decides how to share it (share sheet).
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface CGDiagnosticsExporter : NSObject

+ (NSString *)reportWithConfigDictionary:(nullable NSDictionary *)config
                                 battery:(nullable NSDictionary *)battery
                             diagnostics:(nullable NSDictionary *)diagnostics
                        analyticsSummary:(nullable NSString *)analyticsSummary
                                 appVersion:(nullable NSString *)appVersion;

@end

NS_ASSUME_NONNULL_END
