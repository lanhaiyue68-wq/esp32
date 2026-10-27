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

Five regression tests were first committed against build77 source at f011955. RED run: 40439396466. Production changes and full build78 verification pending. No physical phone is connected to this workstation; simulator tests cannot establish real HID accuracy.

## Routing and data handling

Systematic-debugging and test-driven-development skills; Git/gh, local bounded ZIP inspection, firmware/source tracing. Headroom was invoked on the selected diagnostic log, but its local model is unavailable and it returned passthrough. Raw logs/screenshots remain outside Git under the local log39-inspection directory. Only synthetic tests and this sanitised causal summary are committed.
