//
//  CGPresetManager.h
//  ChargeGuard v3.0 — one-tap presets + cl URL scheme (new feature)
//
//  Presets only produce a CGConfig. Applying one still goes through
//  CGDaemonClient's gated write path and only happens on an explicit
//  user tap in the UI — a preset can never apply itself, and it never
//  touches temperature, schedule or Optimized Battery Charging settings.
//  The cl URL scheme (already supported by the app: cl:///charge,
//  cl:///nocharge) is generated here so automation shortcuts use one
//  canonical form.
//

#import <Foundation/Foundation.h>

@class CGConfig;

NS_ASSUME_NONNULL_BEGIN

@interface CGPreset : NSObject
@property (nonatomic, copy, readonly) NSString *identifier;
@property (nonatomic, copy, readonly) NSString *title;
@property (nonatomic, copy, readonly) NSString *subtitle;
@property (nonatomic, assign, readonly) NSInteger stopChargeAbove;
- (instancetype)initWithIdentifier:(NSString *)identifier
                             title:(NSString *)title
                          subtitle:(NSString *)subtitle
                   stopChargeAbove:(NSInteger)stopChargeAbove;
@end

@interface CGPresetManager : NSObject

+ (NSArray<CGPreset *> *)allPresets;
// A copy of base with only the preset's stop threshold changed.
+ (CGConfig *)configByApplyingPreset:(CGPreset *)preset toBaseConfig:(CGConfig *)base;
// Canonical cl URLs for automation (Shortcuts / URL scheme).
+ (NSURL *)chargeURL;
+ (NSURL *)noChargeURL;
+ (NSURL *)chargeURLWithExit:(BOOL)exitAfter;

@end

NS_ASSUME_NONNULL_END
