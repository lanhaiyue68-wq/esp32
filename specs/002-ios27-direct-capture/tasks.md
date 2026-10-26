# Tasks

- [x] T001 Record approved scope, constraints, acceptance and source routing.
- [x] T002 US2 Write/run failing Foundation frame-policy tests.
- [x] T003 US1/US2 Implement native whole-display capture, frame timing and lifecycle safety.
- [x] T004 US1 Route existing frame consumers, board status and recovery consistently.
- [x] T005 US3 Add source/share UI, readiness and actionable interrupted-state handling.
- [x] T006 US4 Add local coalescing, bounded conversion and source/OS diagnostics.
- [x] T007 US5 Run policy and simulator regression tests, compile unsigned IPA, inspect packaged metadata.
- [x] T008 US5 Review races, stale frames, stop/restart, source switching, calibration and preserved input; fix findings and reverify.
- [x] T009 US5 Write test instructions, validation record and convergence review; deliver exact artifact.

Dependencies: T002 → T003 → T004/T005/T006 → T007 → T008 → T009. No agent delegation requested. Real-device acceptance is performed with the user-installed signed build and exported logs, not inferred from simulator tests.
