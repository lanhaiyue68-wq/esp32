# iOS 27 direct screen capture preview

Approved intent: the user requested a build of the discussed phone-native capture plan, keeping wireless ESP32 control and the charging port free, followed by bug review. This preview replaces observation first; measured speed and real-device acceptance remain explicit checks.

## Stories and acceptance

- US1 (P1): On iOS 27, choose direct capture and authorize whole-display sharing in Apple's picker. The existing agent, pointer, calibration, recording and WeChat watch consume its frames without requiring AirPlay or USB.
- US2 (P1): Switching apps keeps receiving native frames. A stopped, suspended, blank, app-only, stale or superseded capture cannot authorize device actions. Existing board connectivity checks still apply. Recovery requires valid frames from the current sharing session.
- US3 (P1): Show capture source and sharing state, with explicit start/stop controls and actionable errors. Preserve a selectable legacy mirror source and build73 input preservation.
- US4 (P2): Bound local conversion to approximately 4 FPS, keep the newest image, and never convert capture FPS into model-request FPS. Record source, frame age, OS and interruption details in diagnostics.
- US5 (P1): Deliver an unsigned device IPA compiled with the iOS27 SDK, with fresh relevant tests, full regression results and a review. State device-only checks honestly.

## Constraints

No firmware flashing, USB requirement, new hardware, microphone/camera capture, model/provider change, automatic cloud streaming, global removal of action checks, or claims of measured speed without a matched successful-task comparison. Portrait is the current app's supported device orientation. Protected/unavailable content must pause rather than be treated as a usable screenshot.

## Success criteria

SC1: Native capture starts through system consent and the source routes every existing screen consumer consistently.
SC2: Policy tests reject stale session callbacks, app-only capture, invalid timestamps, interruption and old images after an action; genuine idle events may confirm unchanged pixels.
SC3: Device build, policy tests and existing simulator tests pass on Xcode27; test artifacts identify their exact commit.
SC4: Instructions describe install/signing, whole-screen sharing, wireless controls, interruptions and export of comparable logs. Cross-app/background/BLE behavior is marked pending until tested on the user's phone.
