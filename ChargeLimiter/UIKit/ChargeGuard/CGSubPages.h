//
//  CGSubPages.h
//  ChargeGuard v3.0 — redesigned sub-pages (deep redo, 2026-11-01)
//
//  Each page is complete in itself: it reads and writes through
//  CGDaemonClient (and, for app-local settings, CLBatteryManager / the
//  shared local store) and never routes to a legacy page. The legacy
//  controllers still exist in the codebase but are not referenced from
//  these pages. Help is unchanged (its v2.0 single-link design is kept)
//  and is routed from the main page.
//

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

// History: in-page chart (5 min / hour / day / month, current / voltage
// overlays), real statistics switch, analytics summary, filtered policy
// timeline in plain Chinese.
@interface CGHistoryAnalyticsViewController : UIViewController
@end

// Compat test: precheck + the real compat engine run in-page, per-path
// result cards, overall verdict, and the charge-control probe.
@interface CGCompatResultViewController : UIViewController
@end

// Advanced: every control switch and value from the old advanced page,
// written in-page through CGDaemonClient, with the old interlocks kept.
@interface CGAdvancedViewController : UIViewController
@end

// Software: version + in-page update check, diagnostics export,
// automation links, refresh rate, language, appearance, notification,
// haptics, log level, preset shortcut, data-dir path copy, legacy-data
// migration — all in-page.
@interface CGSoftwareViewController : UIViewController
@end

NS_ASSUME_NONNULL_END
