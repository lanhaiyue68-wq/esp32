# Changelog

## Build 71 (2026-10-26)

- Restore and verify the original app after a clipboard hop; stop typing when the destination cannot be verified.
- Recognize joined QWERTY OCR labels and preserve the concrete goal for bare retry requests.
- Bound unchanged Home recovery, verify a single send without sending again, and report unconfirmed outcomes accurately.
- Unsigned device build and all 340 simulator tests passed (CI 40323966996); physical iPhone verification pending.

## Unreleased (main)

- No computer: the ESP32 is the AirPlay receiver (ported from UxPlay) with its own hotspot, and talks to a new
  iPhone app over BLE. The app is the agent: planner/actor loop, pointer calibration, run replay, Live Activity,
  widgets, Siri and Shortcuts, self-healing when the board, hotspot or mirroring drops.
- Prompts moved to `prompts/`.
- Product name: ESP32 Agent.
- `server/` is legacy and no longer needed.

## v0.1.0

- Computer-side version: UxPlay + Python server + web UI; the ESP32 is a USB HID bridge over Wi-Fi.
