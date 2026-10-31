//
//  CGSubPages.h
//  ChargeGuard v3.0 — redesigned sub-pages (new layered architecture)
//
//  Each page renders a new layout and reads through CGDaemonClient only.
//  Each keeps one button to its legacy full page, so no legacy function
//  is deleted: the new page is the redesigned front door, the legacy
//  page remains the complete back room. Help is unchanged (its v2.0
//  single-link design is kept) and is routed from the main page.
//

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

// History: capsule filters + analytics summary + coloured policy timeline.
@interface CGHistoryAnalyticsViewController : UIViewController
@end

// Compat test: large conclusion card + run the legacy full test.
@interface CGCompatResultViewController : UIViewController
@end

// Advanced: grouped cards, right-aligned switches for the main switches.
@interface CGAdvancedViewController : UIViewController
@end

// Software: version, update, diagnostics export, automation (cl URLs).
@interface CGSoftwareViewController : UIViewController
@end

NS_ASSUME_NONNULL_END
