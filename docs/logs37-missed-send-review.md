# logs37: a click acknowledgement is not a completed send

## Evidence

The export was produced by build 75 on iOS 27.0.1. The direct display stream was live. At 23:46:16 UTC the local field check accepted the requested input; at 23:46:23 the actor requested tap (908,543). The board acknowledged home, move (255,334), and click. There was no visual pointer aim. The run then entered read-only send verification and failed at 23:46:42.

The actual Claude trace was absent: five later internal report/navigation runs occupied the entire five-run export window. The shared debug log retained the commands, but not the Claude frames. The Claude miss location therefore cannot be established from this export.

The included WeChat report provides a direct before/after comparison of the same defect. The report draft remained complete after tap (863,887). Its post-action frame shows the pointer at approximately (0.97,0.98), below and right of the intended keyboard send control. A later attempt at (863,886) used almost identical board units, landed near the control, and produced a new outgoing bubble. This is evidence of an unreliable open-loop landing, rather than a text-generation error.

## Broken contracts

1. A first send tap used the ordinary fast path. The board acknowledging a relative move established delivery of the command, not its screen endpoint.
2. Precision aiming could return without finding the pointer, lose it during correction, or exhaust corrections; the caller still clicked.
3. The send guard treated a successful HID command as a sent message. Recovery recognized extra letters, but a correct, unchanged draft could only wait until failure.
4. The export window selected the latest five internal runs rather than preserving the owner task within the existing bounded local history.
5. Pixel aiming observed the pointer before its probe, then assumed the inverse mouse move restored that point. A test using actual rendered pointer frames (without the finder shortcut) clicked at x=0.8848 when asked for x=0.863. Probe frames also used a time boundary before command acknowledgement.

## Bounded repair and validation

Regression tests were committed before implementation (`560788b`, `7f8e42d`). RED run40424580741 executed398 tests with11 expected assertions in six regression methods. RED run40425693931 executed401 tests with12 expected assertions, including the real pixel endpoint error. No unrelated regressions appeared. Raw CI output and phone evidence stay outside Git.

The repair must retain correct text, require visual aim for a pending message's send tap, refuse an unverified precision click, and permit only bounded recovery on positive evidence that the same draft remains with no new matching bubble. Unreadable/empty fields and new bubbles retain duplicate protection. The existing storage limits and wireless/direct capture architecture remain in force.

Build76 implementation is ready for full CI. It measures the returned pointer after acknowledged probe movements, refuses an unverified precision click, aims the first send tap, and preserves the raw expected draft for exact inspection. Recovery requires two post-action observations of that same complete field and no new matching message, with at most two recoveries. Empty/unreadable fields retain protection. The export includes up to20 retained runs, within the existing20MB payload and80MB local budgets, excluding video.

Physical-phone success is not claimed by these simulated tests. Original phone data remains outside Git.

## Build validation

The first validation attempt (run40426883061) completed the device build but stalled in the simulator stage without publishing any test progress. It was canceled; no passing test result is inferred. Its candidate IPA was removed locally and from Actions.

Commit1926117 changes CI observability and publication only: stream test output, bound individual test execution, retain failed test logs for one day, and upload the IPA only after passing tests. App sources are identical to f9531e9. Replacement run40428771305 passed: Release device build,401 simulator tests and8 direct capture policy tests, all zero failures. The rendered post-probe pointer test passed in4.188 seconds. Source19261178cee60e645ce66efe4bee4117cc7aedf4 has the same app sources as f9531e9.

Key implementation files:
- ios/IPhoneAgent/Agent/Pointer.swift: actual post-probe position, acknowledgement timing, precision click precondition.
- ios/IPhoneAgent/Agent/AgentLoop.swift: first-send aiming, raw draft retention, bounded evidence-based recovery.
- ios/IPhoneAgent/Agent/CandidatePicker.swift: same-field/no-new-message observations.
- ios/IPhoneAgent/Services/DiagnosticFiles.swift: bounded retained-history export.
- ios/IPhoneAgentTests/Logs37RegressionTests.swift and DiagnosticFilesTests.swift: dispatch, rendered pixels, duplicate protection, export coverage.

## Delivery and cleanup

Verified unsigned build76 is E:/桌面/Lan-Agent-build76-unsigned.ipa (5,262,281 bytes), arm64, native ScreenCaptureKit linked, minimumOS18.0. SHA256:4bf606f017a5e9635fa028bdbb3b626e8efe0ca2965e51321541a65f3380f1c9. Requires signing; physical iPhone acceptance remains unverified.

Desktop and artifact-cache build75 packages, both failed RED artifacts, the canceled candidate, and the duplicate downloaded build76 IPA were removed after verification. Only the final build76 artifact remains in the build repository; the desktop has one current IPA. Source and original diagnostics were retained. Future workflow uploads IPAs only after tests pass, with seven-day retention. Test-failure logs have one-day retention. Cleanup manifests and detailed verification stay in E:/AgentStorage/esp32/log37-inspection.
