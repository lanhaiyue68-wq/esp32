# Implementation review — build74

Scope: current spec/plan/tasks; source routing, consent lifecycle, frame timing, queue ordering, recovery, calibration, watch, recording and preserved build73 input. No firmware or provider changes.

## Findings corrected

- Native readiness must not depend on board AirPlay/STA/video status. Board statuses cannot inject/erase native pixels. Board connectivity still gates control.
- BLE reset/loss previously destroyed legacy decoder pixels; native sharing now survives BLE reconnect independently.
- Native paths must return before all board snap/replay branches, including diagnostic snapshots and command-timeout fallbacks.
- Delayed frames, errors and stop callbacks from replaced streams cannot revive or stop the active generation. Session and sequence checks are enforced twice (owner and feed/policy).
- Real idle events confirm existing pixels but cannot recreate invalidated pixels. They do not change the pixel settling clock or republish recording JPEGs.
- A last changed frame pending in the 250ms conversion throttle must flush even without another changed frame. Idle proof is deferred until that flush, rather than defeating the conversion limit.
- Use the system event display time, or PTS against the stream synchronization clock; never label queue arrival as capture time. Reject old/invalid timestamps.
- Apply system EXIF orientation metadata before checking portrait geometry. Landscape output pauses control.
- Saved legacy snap preference must not block native video calibration.
- Missing sharing, canceled picker and expired confirmation have actionable UI. Sharing stops explicitly; legacy mode remains selectable while idle.

## Verification evidence

- TDD RED: run40404690705 executed 7 policy tests, 10 expected assertion failures against the unimplemented state machine.
- First GREEN: run40406544665 passed Foundation frame policy, unsigned device Release and full simulator regression on commit b17d00c. The final source is verified separately below.
- Nine integration tests cover direct preflight/snap command isolation, board status/decoder isolation, BLE reconnect, stop/replacement callbacks, suspension, idle/settling semantics, no-sharing errors and old invalidations.
- Additional policy test covers clock mapping and queued/invalid timestamps.
- Packager asserts ScreenCaptureKit is actually linked, avoiding a silently excluded implementation under an old SDK.
- Jev numerical review flagged the cross-module size and remaining test gap with low spec confidence; it gave no concrete code finding. It is advisory, not approval authority. Manual source review and deterministic validation remain required.

## Pending device acceptance

System full-display picker, fresh timestamps and idle behavior on the installed iOS27 release, background screen delivery, visible AssistiveTouch cursor, BLE gestures, Chinese input, pause/restart and runtime CPU/thermal behavior. No hardware access or measured speed is inferred from CI.

API basis: [iOS capture](https://developer.apple.com/documentation/screencapturekit/capturing-screen-content-on-ios), [stream clock](https://developer.apple.com/documentation/screencapturekit/scstream/synchronizationclock), [orientation](https://developer.apple.com/documentation/screencapturekit/scstreamframeinfo/videoorientation). Independent implementation uses platform APIs; no third-party capture source was copied.

## Final verification and convergence

- Source commit: `8e8248645be1276daf5333b975c369225126a061`.
- [Final CI run40407538020](https://github.com/ChenQian-hub/esp32-iphone-agent-app/actions/runs/40407538020): **success**. Xcode27.1; 8 Foundation policy tests and 368 simulator tests, zero failures; unsigned device Release passed.
- Downloaded IPA inspected independently: build74, iphoneos27.1 SDK, minimumiOS18.0, `bluetooth-central/audio/screen-capture` background modes, ScreenCaptureKit linked, no signature, ZIP integrity passed.
- SHA256: `c1f1ee76575e01610e03f2e3bed9421ebfc5f4ab77e8018e9c9c79e548c2aaca` (5,177,247 bytes). Desktop copy matches.
- Convergence assessed current code against US1–US5 and SC1–SC4, including all named consumers. No remaining buildable gap within the approved preview scope. No Convergence tasks appended. The unfilled constitution template adds no constraints; no extension hooks are registered.
- Source review preserved build73 text/paste/intent code; it was covered again by the full suite. New source startup, interruption, stale/session/sequence safety, source isolation and BLE recovery are covered by policy/integration tests. System output callbacks and physical gestures remain device acceptance, not simulated success.
- The compiler reports ScreenCaptureKit Sendable annotations under Swift5 compatibility; no Swift6 migration is included. Pixel processing stays on its serial queue; lifecycle and feed mutation stay on MainActor.
- User storage question checked against `TraceStore`/`DiagnosticFiles`: latest/pending capture buffers are replaced; task replay capped at 8MiB/120 frames, step images12MiB, overall diagnostic cleanup thresholds80MiB/20 runs/7days. Images are app-owned files, not Photos. Existing retention implementation was preserved.
