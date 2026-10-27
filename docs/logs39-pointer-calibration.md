# logs39: calibration and screen-sharing interruption

## Evidence and scope

App 77 on iOS 27.0.1. The local diagnostic ZIP contains 20 calibration fits; the worse axis RMS spans 2.20–4.18%. Seventeen of 20 check taps miss by at least 2%. A centre check occasionally looks better than the full fit and masks poor edge accuracy.

At 02:24:50 UTC a back-arrow target (0.054, 0.086) becomes `move 2 19`. At 02:25:14 and 02:26:00 the watch return target becomes `move 4 22`. Each click is followed by capture interruption; the user screenshot shows the native stop-sharing alert over WeChat. The native alert is not in exported captured frames, so the exact physical hit is inferred from this sequence and the supplied photo.

Repeated samples also show the same horizontal units landing at different X coordinates when the vertical distance changes. Firmware `movePaced` emits diagonal packets until one axis finishes, followed by single-axis packets. Its vector speed therefore varies by destination. iOS acceleration is the likely mechanism; a constant, independent per-axis linear mapping is not supported by the phone evidence.

## Implementation requirements

- Use the same settled, separate-axis positioning for calibration and normal taps, without firmware or USB changes.
- Measure edge-relevant positions and use monotone interpolation from home rather than extrapolating an interior offset into the status bar.
- Keep calibration provisional until several fresh click checks pass. Missing checks or errors above 1.5% must not become a successful saved calibration.
- Keep observed fit scatter in reported quality; one good centre check cannot hide it.
- Return from a verified WeChat chat with the middle-edge back gesture and verify the list on a fresh frame.
- Preserve direct iOS 27 capture, general input verification, task authorisation, and the existing learning UI.

## Validation

Five regression tests were first committed against build77 source at f011955. RED run: 40439396466. The five tests failed with seven assertion failures. Source 6ea708b adds 13 regressions in total. Full run [40441518572](https://github.com/winesettbumpas609-boop/esp32-iphone-agent-build/actions/runs/40441518572) passed: Release arm64 build, 421 simulator tests and 8 direct-capture policy tests, zero failures. No physical phone is connected to this workstation; simulator tests cannot establish real HID accuracy.

## Routing and data handling

Systematic-debugging and test-driven-development skills; Git/gh, local bounded ZIP inspection, firmware/source tracing. Headroom was invoked on the selected diagnostic log, but its local model is unavailable and it returned passthrough. Raw logs/screenshots remain outside Git under the local log39-inspection directory. Only synthetic tests and this sanitised causal summary are committed.

## Implementation

`ProbeMap.swift` records a monotone curve and the worst repeated-measurement scatter. `ProbeMotion` separates X/Y positioning with settling delays, using existing board commands. All new gesture starts home consistently; drag trajectories remain continuous. `Pointer.swift` persists a motion version, stages candidates, and restores previous parameters on failed validation. `TouchCalibration.swift` uses four independent validation locations and at most one refinement; `AutoCalibrator.swift` cannot replace missing click checks with an unvalidated video or manual estimate. `WatchListReturn.swift` uses the middle-edge back gesture. No capture API or firmware changes.

## Delivered artifact

Desktop: `E:/桌面/Lan-Agent-build78-unsigned.ipa` (unsigned, build78, version1.0, minimum iOS18, arm64, ScreenCaptureKit linked), 5,267,769 bytes. SHA256 `072d43b2f0756558fcc88173720fcc50d77d2c0a337cecf956a00bad5c1afd30`. ZIP integrity, embedded build and CI hash match. Superseded desktop77 and duplicate78 package removed after verification. Superseded cloud package/test artifacts removed. Temporary RED-only workflow removed; release workflow retains all tests.

Installation on the phone and actual HID accuracy remain unverified. Install/sign build78, complete the new calibration, then send a new task rather than relying on a previously handled request. Failed calibration must show the measured failure rather than continue with unverified parameters.
