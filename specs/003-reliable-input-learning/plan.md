# Implementation Plan: Reliable input and visible learning

## Technical Context
Existing Swift 5 / SwiftUI iOS18+ app with guarded iOS27 ScreenCaptureKit capture, XCTest, XcodeGen and GitHub macOS CI. Windows host cannot compile UIKit locally. Use the current branch and draft PR. No new dependencies, services or firmware.

## Constitution Check
User intent, wireless-only constraints, evidence-based verification and local bounded storage govern. The pre-existing constitution file is an unfilled template, so it contributes no additional decisions. Keep this feature inside existing AgentLoop, CandidatePicker, LessonBook, ExperienceStore and RunSession responsibilities.

## Phase 0: Research
Existing code really persists and retrieves lessons and measured cases; it lacks a direct inspection screen, reference counts/source of use, and visible review outcomes. Only successful non-noisy runs get automatic model review. Preserve that evidence boundary; don't turn failed routes into invented instructions. See research.md.

## Phase 1: Design
- Continue shared input repair; route unsupported Unicode and multiline text through the existing exact paste path even for ordinary tasks. Preserve short verified pinyin, uncertainty retention and duplicate-send guards.
- Make existing learning stores observable. Extend lesson fields with optional disabled/uses/last-use task/run metadata so old arrays still decode.
- Keep a separate capped review journal beside the lesson file, with finite states and no screenshots. A process restart changes abandoned in-progress reviews to interrupted.
- Record review eligibility/status in RunSession; final accepted learnFromRun writes actual retained lesson count. Keep a clear/disable/deletion epoch so late replies cannot resurrect data.
- Add a native LearningView reached by Home and Settings, with actual lesson lists, measured feedback, recent review outcomes and per-item detail/control. Counts never pretend quotation means successful execution.
- Reuse existing run-review UI for available sources; clearly handle cleaned source logs. Localize visible labels with the current catalog.

## Validation
XCTest RED before implementation for general text routing, optional legacy-field filtering, real reference count persistence and actual auto-learning journal creation. Preserve all existing input, storage, learning precedence and epoch tests. CI must compile device Release and pass all tests before IPA delivery. No raw phone diagnostics committed or uploaded as test fixtures.
