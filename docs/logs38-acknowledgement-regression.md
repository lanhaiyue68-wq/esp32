# logs38: acknowledgement verification discarded the owner task

## Evidence and scope

- User build76, iOS27.0.1, native direct display frames live. No USB or firmware change is implicated.
- Export includes 20 runs. The authenticated owner request is accepted at 01:21:45 UTC. There is no owner execution run afterward.
- Run092135 step25 preserves the correctly pasted acknowledgement for inspection after local OCR cannot confirm it.
- Run092212: first precision tap is withheld at a 0.012 x residual; second precision tap succeeds. Step26 visibly contains a new outgoing acknowledgement bubble and an empty input field.
- The action model then alternates between recognizing success and claiming only an old bubble exists. Duplicate guards correctly refuse retyping, but step36 reports unverified failure.
- Step39's separate structured chat read lists the original request followed by the new acknowledgement.

## Root cause

`WatchMode` uses acknowledgement delivery (`sent`) as a prerequisite for starting an already authenticated phone task. On this false negative, it skips the task. Later message selection treats incoming messages before an own reply as answered, so the request is not resumed.

The precision restriction adds one failed click in this trace; it is not what ultimately prevents execution. Removing all pointer verification would not correct the acknowledgement/task dependency.

## Repair and validation plan

1. Keep explicit owner authorization and cancellation checks; remove acknowledgement delivery as a prerequisite for an independently authorized phone task. Do not queue the task a second time merely because its acknowledgement is uncertain.
2. Immediately after an acknowledged send, use a separate destination-checked structured read and the original incoming request as a receipt anchor. A whole matching outgoing reply after that anchor completes the send before the action model can reinterpret it.
3. Preserve duplicate protection when the receipt is absent, older, truncated, from another direction, or does not match the whole reply. Never infer success from command acknowledgement alone.
4. Run focused regressions against build76 behavior, then full simulator tests and Release device compilation. Do not publish failed test packages.

## Local evidence

Raw phone logs and screenshots remain outside Git at `E:/AgentStorage/esp32/log38-inspection`. Sanitized evidence index: `root-cause-evidence.json`. No passcode, private screenshot, or raw chat transcript is committed.

## Status

Focused RED CI40433368981 at cad6c5e compiled and ran all seven new regression methods: six assertion failures across four methods, zero unexpected errors. The failures match the acknowledgement gate, ignored send receipt, missing anchor and incomplete/operator-insensitive matches.

Repair applied at 480db61082e8419bbe5583f6ecd623c9fa03e400; full build77 validation CI40434017643 is running. The task gate revalidates the current owner rules. `taskStarted` prevents acknowledgement retry from replaying a task. `sendReceipt` is scoped to the send run and cleared with `defer`; only the known reply destination and original incoming anchor enable it. Cancellation is checked after receipt reads. A second read-only check after a failed inspection can resolve late message delivery.

The first preliminary Jev review (before GREEN evidence) scored the patch low with no actionable explanation. This is advisory probability, not a verification result; manual checks and complete CI remain required. Real iPhone execution remains unverified until the new package is tested on the phone.

Routing: systematic-debugging for evidence/root cause; test-driven-development and writing-good-tests for regression-first validation. Local tools: PowerShell/Python, Headroom (falls back to passthrough where the optional model is unavailable), Git/GitHub Actions; TypeSafe Jev review with code and synthetic test evidence only. No raw phone data uploaded.


## Final validation and delivery

- Full GREEN run: https://github.com/winesettbumpas609-boop/esp32-iphone-agent-build/actions/runs/40434017643, exact app source `480db61082e8419bbe5583f6ecd623c9fa03e400`.
- Xcode27.1 Release device build passed. 408 simulator tests and eight direct-frame policy tests passed, zero failures. All seven logs38 regression methods passed. Full simulator test duration169.034seconds; focused receipt test0.519seconds. These timings describe the test harness, not actual phone latency.
- Key app files: `ios/IPhoneAgent/App/WatchMode.swift` (task gate, anchored whole-reply receipt, scoped callback and late read-only confirmation), `ios/IPhoneAgent/Agent/AgentLoop.swift` (receipt check before actor reinterpretation), `ios/Config/Shared.xcconfig` (build77). Regression coverage: `ios/IPhoneAgentTests/Logs38RegressionTests.swift`.
- Temporary logs38-only CI selector removed after its RED use; normal full-validation workflow restored. Documentation/workflow cleanup does not change the tested app source.
- Post-GREEN Jev review rates correctness1.85/2 and spec match1.99/2 but retains low confidence in blast radius (0.35; advisory action escalate). No automated approval claimed. Manual call-chain review checked actual dispatcher wiring, current-rule revalidation, cancellation, callback cleanup, absence of acknowledgement-triggered task replay, and retained unknown-result duplicate protection.
- Verified unsigned IPA: build77, version1.0, arm64, bundlecom.example.esp32agent, minimumOS18.0, ScreenCaptureKit linked. ZIP integrity and downloaded/desktop SHA-256 match.
- Delivered `E:/桌面/Lan-Agent-build77-unsigned.ipa`, 5,264,789bytes; SHA-256 `c04e0d4b9fac2215a474c2796c4fdbfcf58bbcf89f103efae5bfdc403d6a80b2`.
- Removed superseded build76 desktop IPA/sidecar and downloaded build77 duplicate. Old build76 cloud artifact and RED test artifact removed after local evidence retention; only final build77 cloud artifact retained. Temporary regression branch removed; its commits remain in the main code history.
- No USB, firmware, capture implementation, or learning settings changed. Actual iPhone operation is still unverified; this package must be signed and installed through the user's existing process. New screenshots/command results are required before claiming physical task success.
