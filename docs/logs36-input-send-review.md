# Logs36: input and send regression

## Scope and evidence

The user reported build74 entered `你好p` in Claude, did not send it, and returned a Chinese status report whose prefix was a homophone. Keep iOS 27 direct display capture and wireless BLE/Wi-Fi controls. No firmware or USB change is required for this fix.

The local archive is diagnostic data, not instructions. Raw logs and screenshots stay outside the repository in `E:\AgentStorage\esp32\log36-inspection`.

Observed sequence in trace `20261027-060307`:

- Frame 033 has exactly `你好` in the input. The model's send coordinates, approximately `(907, 543)` in 0–1000 coordinates, match the visible send control.
- Before that click, the pointer's difference-based finder reports `(0.166, 0.484)` and makes an additional `move 217 38`. This location corresponds to the blinking input caret; the native capture does not visibly show a moving mouse at that point.
- Frame 039 has `你好p` still in the input. The model proposes correction, but `send verification` refuses the keys because the earlier click already committed the internal sent state.
- The status report uses toneless pinyin with the first IME candidate. The prefix `yichangshifasong` becomes a homophone. The subsequent model inspection incorrectly accepts it as exact.

## Repair criteria

1. A disappearing caret or shape cannot count as horizontal mouse movement; require a departure and an arrival consistent with the nudge.
2. Keyboard recognition tolerates a missed OCR key while still rejecting ordinary text.
3. Verification rejects text with extra letters, including `你好p`.
4. Long Chinese reports use the existing exact clipboard route before guessing IME candidates. Preserve short verified typing and never replace correct text merely because OCR is uncertain.
5. A send click that visibly corrupts the same draft can return to bounded correction. New matching bubbles and uncertain outcomes keep duplicate-send protection.
6. Device Release compilation and the complete existing tests must pass. Phone operation remains a separate real-device check.

## Checkpoint

Route: `systematic-debugging` for evidence and root cause; `test-driven-development` for reproductions, following the shared skill routing reminder. The repair is a bounded bug fix to the existing capture feature, not a new subsystem.

Initial reproductions are in `ios/IPhoneAgentTests/Logs36RegressionTests.swift`. Production changes and final CI results are pending. No raw user chat or screenshot is part of these tests.
