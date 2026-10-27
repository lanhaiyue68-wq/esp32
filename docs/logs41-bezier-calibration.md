# build80: preserve Bezier and invert measured low-coordinate plateaus

The user explicitly requires Bezier pointer motion. Build79 incorrectly persisted `curve off` for both calibration and normal positioning. Build80 removes that command, confirms `curve on` before measured homing, and restores boards left off by build79. An already enabled board is only queried; unconfirmed replies and timeouts stop positioning. Only an explicit unsupported-command reply permits older straight-only firmware. Firmware code is unchanged; no USB or flashing is required.

Logs41 also proves that disabling curves did not solve calibration. Several build79 rounds repeatedly target y=0.09 but land at y=0.109. Commands 46 and 56 both land at 0.109; 75 lands at 0.149. `ProbeMap` collapsed this measured plateau to its midpoint and interpolated towards an invented physical (0,0) landing. Refinement consequently still selected 42 units and repeated the miss. The logs also include a real 17.2% outlier; this change does not discard it or claim that every miss is a modelling error.

The map now retains the measured unit interval for every flat response. Below the first measured landing, inversion uses the measured low-end gain and the leading edge of the plateau; the logs41 fixture yields 32 units instead of 42. A response without measurable span is rejected, and inconsistent repeated commands still contribute their actual scatter. This fixes a demonstrated inverse-model defect; it cannot prove how a new curved move will land on a real phone.

Calibration and runtime both use Bezier movement. Version3 marks older mappings stale, including build79's straight calibration. Sampling remains seven initial measurements and four fresh checks, with at most one four-check refinement. The 1.5% acceptance limit and save-only-after-fresh-checks rule are unchanged. Existing input, send, task, capture and learning safeguards are untouched.

Skill routing: systematic-debugging and test-driven-development, with Spec Kit triage. These are two bounded defects in the existing motion preference and inverse map; no new subsystem or workflow rewrite was introduced. Raw logs remain local outside Git.

RED evidence: run40450154361 reproduced five failing Bezier-contract tests (11 assertions); run40450951228 also reproduced the two logs41 plateau tests (four assertions). Both ran unchanged build79 production code. The permanent Foundation harness extracts the real production fit/map/motion code and tests 12 contracts.

Final CI run `40451309403`, attempt1, passed the unsigned arm64 Release build, all 423 simulator tests, 12 Bezier/map policy tests and eight direct-capture policy tests. No tests were skipped. Source: `6f213bd75fafb12c1e0510cdef6374af7aa62593`.

Delivered: `E:/桌面/Lan-Agent-build80-unsigned.ipa`, 5,269,123 bytes, SHA256 `c2795d45fbb81e1f6df82729e0340fc586573c600a36d886e4a772d72ddd1b76`. ZIP integrity, arm64, ScreenCaptureKit linkage and matching build80 in the app and embedded extension were verified. Superseded desktop build79, the duplicate downloaded IPA and old cloud package were removed after verifying the new desktop copy. Re-sign/install and remeasure calibration once; physical-phone landing precision has not been verified here.

Key files: `ios/IPhoneAgent/Agent/ProbeMap.swift` (Bezier preference recovery and inverse map), `Agent/Pointer.swift` (saved motion-version validation), `App/TouchCalibration.swift` (accurate mode label), `tools/pointer-motion-tests` (production-source regression harness), and the corresponding iOS regression fixtures.
