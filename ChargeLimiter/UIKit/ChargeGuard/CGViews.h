//
//  CGViews.h
//  ChargeGuard v3.0 — new views (hero, stat grid, entry grid)
//
//  Views only render. They never call the daemon, never read config
//  themselves, and never write anything. All data arrives from a
//  view model or from the owning controller.
//

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

// Gradient hero card: big percent, status, two pills (mode / adapter).
@interface CGHeroView : UIView
- (void)updateWithPercentText:(NSString *)percentText
                   statusText:(NSString *)statusText
                modePillText:(NSString *)modePillText
             adapterPillText:(NSString *)adapterPillText
                  isCharging:(BOOL)isCharging;
@end

// 2-column stat grid. Items: @{@"title":..., @"value":..., @"subtitle":...}.
@interface CGStatGridView : UIView
- (void)updateWithItems:(NSArray<NSDictionary *> *)items;
@end

// 2-column large icon entry grid. Each entry: title, subtitle, icon name
// (SF Symbol), and a tap block. Tapping never changes config by itself;
// the owner decides what the tap routes to.
@interface CGEntryGridView : UIView
- (void)updateWithEntries:(NSArray<NSDictionary *> *)entries
               tapHandler:(void (^)(NSInteger index))tapHandler;
@end

// Capsule filter control for the redesigned history page.
@interface CGCapsuleFilterView : UIView
- (instancetype)initWithTitles:(NSArray<NSString *> *)titles
                selectedIndex:(NSInteger)selectedIndex
                  changeHandler:(void (^)(NSInteger index))changeHandler;
@property (nonatomic, assign, readonly) NSInteger selectedIndex;
@end

NS_ASSUME_NONNULL_END
