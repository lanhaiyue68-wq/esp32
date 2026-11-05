# logs46: dark keyboard refused, app switch withheld, bring-back task held

Raw logs stay outside Git (E:/AgentStorage/esp32/logs46-inspection). Build83, 2026-10-29 02:09–02:15 Taipei.

- Calibration passed (±1.3%): real-click landing correction took the unseen first check from 3.0% to 0.2%.
- The phone was in the dark appearance (frame mean luminance 44; earlier daytime logs 228). Every reply and the
  Claude task were refused "Not typed: no keyboard is on screen" while the keyboard was up: text recognition read
  none of the dark keyboard's single letters. After two refusals the reply went through the paste hop.
- Paste hop 1: the visible pointer stayed at x 0.210 for the home-bar spot 0.200; the 0.8% aim tolerance withheld
  the app switch. Paste hop 2: the previous app was Claude, so two switches never reached Lan Agent.
- Owner task "去 claude 说一句你好，并把 claude 回复的内容发给我": "并把…发给我" did not count as a second part, so
  after "你好" the run was held to verifying that send (no navigation), the model kept trying to go back to WeChat,
  and the run failed with Claude's reply on screen. Nothing was reported back.

## Build84

- Vision.letterKeyboard finds a letter keyboard by its layout (a row of ten even keys with a row of nine one pitch
  below; keys brighter than the tray in both appearances). Offline on all 110 logs43/logs46 frames: 24 dark and
  29 light keyboard frames found, 57 frames without a keyboard (home screen, chats, Claude, file page) not.
  CandidatePicker.keyboardUp uses it before text recognition.
- System edge swipes accept 3% along the border; across it stays exact. Ordinary taps keep 0.8%.
- Bringing something back (并把/发给我/告诉我/…) counts as a part after the send, and the phone-task prompt says to
  finish with the reply in the answer (the program sends it to WeChat) instead of going back to WeChat.
