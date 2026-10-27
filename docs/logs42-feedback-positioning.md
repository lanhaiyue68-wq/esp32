# logs42: curved positioning requires measured endpoint feedback

## Evidence and decision

Build80 restores Bezier correctly. The eight new rounds at 05:06–05:10Z still fail. Identical `(150,150)` commands land at X0.541–0.604; identical `(238,465)` land at X0.843–0.873 and Y0.759–0.822. Several rounds show X0.483 after `(143,54)` but X0.453 after `(143,374)`. A stable independent one-dimensional inverse map cannot certify this variable coupled motion. Further interpolation changes cannot remove that uncertainty.

The existing pointer already has a bounded visual feedback controller. Reuse it for measured curved calibration and runtime positioning. Keep original firmware Bezier, the saved `curve on` preference, wireless operation, input/send protections and the learning UI. Do not add firmware requirements or a new motion generator. This is a bounded repair of the existing controller; Spec Kit triage does not require a new subsystem pipeline.

## Plan and acceptance

- Write failing behavior tests against build80 before changing production code.
- Persist that this calibration requires endpoint feedback. Plain taps and gesture starts must obey it after restart.
- Raw touch samples estimate scale and retain their scatter. Four fresh real clicks, each after visual correction, must be within1.5%; no raw sample is deleted or claimed to have become more accurate.
- Missing/ambiguous visual feedback or a remaining miss withholds click/press and leaves calibration unsaved.
- The pixel pointer finder must infer the actual nudge displacement instead of subtracting a displacement guessed from the uncertain map.
- Run targeted RED tests, then the complete existing suite and unsigned Release build. No claim of physical phone precision from simulator tests.
- Use a private repository under the user's newly logged-in GitHub owner. Phone logs and screenshots stay local. Replace/clean old packages only after verifying the new IPA.

## Status

- RED against build80 (`f9b616c`, run40455498579): 17 targeted tests, 11 assertion failures. Plain taps clicked X0.453/0.532 for target0.5; missing feedback still allowed click/press. The nudge finder also mislocated an18px translation when the guessed distance was12px.
- Initial implementation (`289f6ab`, run40456017510): the same17 targeted tests pass with0 failures. Saved calibration now requires measured feedback after restart; the original curve generator is unchanged. Raw scatter is retained, while final quality records actual corrected clicks.
- Review RED (`04e1377`, run40456700733):21 targeted tests,2 failures. Mandatory exact-centre aiming prevented back/app-switch gestures when the visible cursor remained inset at the screen border. Added a scoped system-gesture edge-start policy (2.5% visible-centre inset only on an extreme target axis); the other axis and all ordinary/calibration taps keep the original0.8% aim tolerance. The1.5% real-click calibration gate is unchanged. A bottom pinning move is checked again before pressing.
- Full simulator suite, Release compilation and build81 package verification pending. Simulator results do not certify the user's physical iPhone. No firmware flashing or USB connection is required.
- Private build mirror: `caoshihui5211314-cloud/esp32-iphone-agent-build`; main account `lanhaiyue-web` has accepted collaborator access. Raw logs and images remain outside Git.

## Files and validation

`Pointer.swift` persists/enforces feedback and limits correction attempts; `Vision.swift` uses observed nudge translation; `TouchCalibration.swift` requires four fresh corrected physical clicks; `ProbeMap.swift` invalidates older open-loop calibration certification. `Logs42RegressionTests.swift` and `VisionTests.swift` cover the failure classes. The permanent IPA workflow runs the complete suite; the temporary diagnostic-only workflow is removed for final delivery.

Routing: systematic-debugging → test-driven-development, bounded-repair triage with spec-kit-orchestration, existing-controller reuse with ponytail, verification-before-completion. Browser-only computer-use was needed for the new owner's private repository and invitation; subsequent builds use GitHub CLI.
