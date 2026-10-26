# Implementation plan

Use the existing VideoFeed/ScreenSource boundary so all screen consumers keep one source. Add a native ScreenCaptureKit owner and a Foundation-only frame validity state, with source-aware branches in VideoFeed. Use the system picker, screen output only, local JPEG rendering and session generations. Distinguish pixel capture time from an idle callback confirming unchanged content; never refresh validity from a timer.

Keep BLE commands and existing firmware protocol. In native mode, board AirPlay status and Wi-Fi video cannot overwrite native readiness or inject legacy frames. Native start/stop must not issue board snapshots. Board disconnection must still prevent gestures; a BLE reconnect must not erase the separate system capture session.

Expose source/start/stop controls on the existing mirror setup page. Route Home readiness, WeChat watch, recovery, diagnostics, calibration and run startup through the chosen source. Preserve compatibility mode and all build73 input checks.

Use Xcode27's hosted runner for SDK compilation. First run real Foundation policy tests against a minimal unimplemented state to establish RED; then implement and run GREEN, full XCTest regression, device archive and a focused bug review. Use no new external library or copied third-party implementation. Apple docs and a fixed reference implementation are API references only.

Constitution check: user authority, wireless operation, bounded work, no stale-pixel actions, existing architectures, meaningful verification and explicit remaining device checks. The placeholder project constitution is not treated as extra authorization.
