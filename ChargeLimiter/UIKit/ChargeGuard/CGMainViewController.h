//
//  CGMainViewController.h
//  ChargeGuard v3.0 — new main page (new layered architecture)
//
//  Replaces the old single-column main page as the app's root content.
//  It renders only through CGHeroView / CGStatGridView / CGEntryGridView
//  and a CGBatteryViewModel, talks to the daemon only through
//  CGDaemonClient, and routes history / compat / advanced / software
//  to the new CG* pages (which keep a button to the legacy full pages,
//  so no function is deleted). The old CLSettingsViewController stays
//  in the binary as a fallback and is no longer the root.
//

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface CGMainViewController : UIViewController
@end

NS_ASSUME_NONNULL_END
