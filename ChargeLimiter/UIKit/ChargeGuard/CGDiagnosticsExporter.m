//
// CGDiagnosticsExporter.m
// ChargeGuard v3.0 — diagnostics exporter implementation.
//

#import "CGDiagnosticsExporter.h"

@implementation CGDiagnosticsExporter

+ (NSString *)reportWithConfigDictionary:(NSDictionary *)config
battery:(NSDictionary *)battery
diagnostics:(NSDictionary *)diagnostics
analyticsSummary:(NSString *)analyticsSummary
appVersion:(NSString *)appVersion {
NSMutableString *report = [NSMutableString string];
[report appendFormat:@"ChargeGuard 诊断报告\n版本：%@\n生成时间：%@\n\n", appVersion?: @"未知", [NSDate date]];
[report appendString:@"（只读快照，不代表已确认的守护进程状态以外的任何含义）\n"];
if (config.count == 0) {
[report appendString:@"未读取到配置（守护进程可能离线）。\n"];
} else {
[report appendFormat:@"停充 ≥%@%%，开始充电 ≤%@%%，高温停充 ≥%@℃，降温恢复 ≤%@℃\n",
config[@"charge_above"]?: @"?", config[@"charge_below"]?: @"?",
config[@"charge_temp_above"]?: @"?", config[@"charge_temp_below"]?: @"?"];
}
[report appendString:@"\n\n"];
if (battery.count == 0) {
[report appendString:@"未读取到电池数据。\n"];
} else {
[report appendFormat:@"电量 %@%%，电流 %@ mA，电压 %@ V，温度 %@℃，健康度 %@%%，循环 %@ 次\n",
battery[@"CurrentCapacity"]?: @"?", battery[@"InstantAmperage"]?: battery[@"Amperage"]?: @"?",
battery[@"Voltage"]?: @"?", battery[@"Temperature"]?: @"?",
battery[@"Health"]?: @"?", battery[@"CycleCount"]?: @"?"];
}
if (analyticsSummary.length > 0) {
[report appendString:@"\n\n"];
[report appendString:analyticsSummary];
[report appendString:@"\n"];
}
if (diagnostics.count > 0) {
[report appendString:@"\n\n"];
[report appendString:[diagnostics description]];
[report appendString:@"\n"];
}
[report appendString:@"\n注：软件停充不是物理断电，停充后残留几十毫安电流属于正常软停。本报告不修改任何配置。\n"];
return [report copy];
}

@end
