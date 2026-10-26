# Feature Specification: Reliable input and visible learning

**Branch**: `codex/fix-logs32-task-execution`  
**Created**: 2026-10-27  
**Status**: Authorized by the user's request to fix input for all tasks and add an autonomous learning entry.

## User Scenarios & Testing

### User Story 1 - Correct text in any task (P1)
A user asks the phone agent to enter text in any supported application. Text must be checked against the requested content; an extra letter or Chinese homophone cannot count as correct. A correct field stays intact when recognition is uncertain.

Acceptance: ordinary greetings, other short phrases, long Chinese reports, Latin text and wrapped text share the same checking path. A blinking insertion caret does not steer the mouse. A misplaced send can be corrected only with positive draft evidence; confirmed or uncertain sends keep duplicate protection. An unsent message cannot be reported as complete.

### User Story 2 - Inspect real autonomous learning (P1)
The user opens Learning from the main page or Settings and sees actual stored lessons, their source tasks and runs, when they were learned and last quoted, and whether they came from the agent or human feedback. An empty store clearly says that it is empty.

Acceptance: automatic summaries and human teaching are separately labelled. A lesson's reference count and last reference task/run survive restart and increase only when it is supplied to a task. References are not labelled as successful outcomes.

### User Story 3 - Understand and control learning (P2)
The user sees whether recent tasks were reviewed, yielded lessons, were skipped, or failed to review. They can disable learning, disable an individual lesson, delete it, or inspect its source run when available.

Acceptance: disabled/deleted lessons are excluded from subsequent requests. An in-flight review cannot restore erased or disabled data. Unfinished tasks do not generate guessed success routes. Existing measured tap feedback remains visible as evidence, not a claimed successful skill.

### Edge Cases

- Empty, unreadable or stale frames; split OCR observations; custom or partly recognized keyboards.
- Already sent matching bubbles; same-position corrupted draft; repeated failed corrections.
- Old lesson files, repeated lessons, capped stores, source logs cleaned up, app restart during review.
- Disabled learning, manual corrections overriding automatic guesses, model review errors, no reliable lesson.

## Requirements

- FR-001: Apply corrections to shared input/capture/action logic without specific greeting, app or coordinate exceptions.
- FR-002: Preserve verified text and never delete it solely because recognition is uncertain.
- FR-003: Use exact transport for long non-ASCII text and reject extra alphanumeric characters during verification.
- FR-004: Keep bounded send recovery and duplicate protection with fresh visible evidence.
- FR-005: Add directly discoverable Learning entries on Home and Settings.
- FR-006: Show real lesson content, type, source task/run, learned time, reinforcement and reference history.
- FR-007: Persist bounded review status and reasons; do not count skipped or failed reviews as learned lessons.
- FR-008: Support global learning control and per-lesson disabling/deletion with persistence and cancellation epochs.
- FR-009: Keep current local storage caps; no screenshots or continuous model calls for the Learning page.
- FR-010: Preserve iOS27 direct capture, existing BLE/Wi-Fi controls and old stored lessons. No USB or firmware change.

## Key Entities

- Lesson: existing instruction with automatic/human provenance, source task/run, dates, enabled state and real reference metadata.
- Review event: bounded local record of one task's review status, reason and number of retained lessons.
- Measured case: existing uncertain or human-rated operation evidence; never labelled a verified skill without a human verdict.

## Assumptions

Learning means retrieving durable local operation experience for future requests. It does not mean retraining model weights. Reuse the existing successful-run reviewer and measured feedback; keep failed-run guesses out of active instructions. No guarantee that every third-party application or keyboard is operable without device verification.

## Success Criteria

- SC-001: Every input regression and the full existing suite passes on the device-build toolchain.
- SC-002: Learning is reachable from Home and Settings and never shows fabricated examples as actual learning.
- SC-003: Learn, quote twice, restart: content, provenance and a reference count of two are retained.
- SC-004: Disable/delete a lesson: it is absent from later request context, including after restart.
- SC-005: Recent review status distinguishes learned, no reliable lesson, skipped, failed and interrupted; opening the page makes zero model requests.
- SC-006: Delivered unsigned IPA has the expected build number, checksum and a passing CI run; real-device limits are reported.
