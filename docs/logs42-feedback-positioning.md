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

Investigation complete; regression tests written; production unchanged. CI execution and implementation pending.
