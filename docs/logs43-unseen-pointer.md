# logs43: build81 withheld every tap it could not see

## Evidence (raw logs stay outside Git: E:/AgentStorage/esp32/logs43-inspection)

- Build81, firmware v34, curve on. Calibration failed three times in a row with "无法确认曲线终点", always on the
  first check (0.06, 0.50): twice "pointer not found", once "lost during correction". The fourth try passed (±0.8%).
- Both watch runs then failed on step 1: the model asked to tap WeChat on the home screen (0.85, 0.59), the pixel
  diff never found the pointer there, the click was withheld, and three withheld taps ended the run.
- Across the whole export, `aim` found the pointer only on the plain calibration board and WeChat's plain screens.

## Cause

`Vision.pointer` requires the moved pixels to keep their values (`a(x) ≈ b(x + dx)`). The AssistiveTouch pointer is
translucent (≈47% grey), so over icons, wallpaper, the 50% grid line, axis labels or an earlier probe's green
landing dot it changes different values at its two spots. Offline, with the frame's own cursor pasted onto the
logs43 home-screen frame, the detector found it in 30 of 300 places and failed exactly at the WeChat icon; on
WeChat's plain screens it found 250 of 300. A shape-only match found more but was off by >1.5% in up to a quarter
of its hits, so it was not adopted.

Build81 made that detector a precondition for every ordinary click and gesture start (`requiresFeedback`).

## Build82

- Ordinary taps and gestures under a feedback calibration still correct the endpoint when the pointer is seen. When
  it is not seen they click at the calibrated estimate (build77's working behaviour); when it is lost during a
  correction they re-home and click at the estimate. A pointer seen and still off target after the passes is still
  withheld.
- Precision taps (`aim: true`, e.g. a pending message's send button) stay strict: unseen or lost never clicks.
- The calibration board shows plain white (corner squares only) during the four checks, so the check endpoints are
  measured on the background the detector handles. The real click landing still decides the 1.5% check.

## logs44 / build83: checks correct from the real click

- Build82 on the phone: the first check (0.06, 0.50) was still unseen on the plain board, the click landed at
  (0.090, 0.493), 3.0% off, and calibration failed. The same curved command scatters by up to 5% between tries
  (move 140 75 landed at x 0.480 and 0.530), so an unseen check can rarely pass 1.5%.
- The board catches every real click. Each check now clicks once (pixel-corrected when seen, otherwise at the map
  estimate, or in place if the pixel correction gave up), then up to twice moves the resting pointer by the measured
  landing miss and clicks again. The final real landing must still be within 1.5%. The board waits 0.4 s to repaint
  plain before the first check.
