//
//  CGPresetManager.m
//  ChargeGuard v3.0 — presets implementation.
//

#import "CGPresetManager.h"
#import "CGConfig.h"

@implementation CGPreset

- (instancetype)initWithIdentifier:(NSString *)identifier
                             title:(NSString *)title
                          subtitle:(NSString *)subtitle
                   stopChargeAbove:(NSInteger)stopChargeAbove {
    self = [super init];
    if (self != nil) {
        _identifier = [identifier copy];
        _title = [title copy];
        _subtitle = [subtitle copy];
        _stopChargeAbove = stopChargeAbove;
    }
    return self;
}

@end

@implementation CGPresetManager

+ (NSArray<CGPreset *> *)allPresets {
    return @[
        [[CGPreset alloc] initWithIdentifier:@"daily-80" title:@"日常 80%" subtitle:@"延长电池寿命的日常值" stopChargeAbove:80],
        [[CGPreset alloc] initWithIdentifier:@"long-life-60" title:@"长寿 60%" subtitle:@"长期插电时更保守" stopChargeAbove:60],
        [[CGPreset alloc] initWithIdentifier:@"travel-100" title:@"出行 100%" subtitle:@"出门前充满一次" stopChargeAbove:100],
    ];
}

+ (CGConfig *)configByApplyingPreset:(CGPreset *)preset toBaseConfig:(CGConfig *)base {
    CGConfig *copy = [base copy];
    copy.stopChargeAbove = preset.stopChargeAbove;
    return copy;
}

+ (NSURL *)chargeURL {
    return [NSURL URLWithString:@"cl:///charge"];
}

+ (NSURL *)noChargeURL {
    return [NSURL URLWithString:@"cl:///nocharge"];
}

+ (NSURL *)chargeURLWithExit:(BOOL)exitAfter {
    return [NSURL URLWithString:exitAfter ? @"cl:///charge/exit" : @"cl:///charge"];
}

@end
