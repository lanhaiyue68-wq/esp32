# Tasks: Reliable input and visible learning

- [x] T001 Audit shared typing, learning persistence/retrieval and UI entry points; document specification and design.
- [x] T002 [US1] Prove general text routing regressions with XCTest in ios/IPhoneAgentTests/LearningVisibilityTests.swift.
- [x] T003 [US1] Route multiline and unsupported keyboard text through exact paste in AgentLoop.swift and CandidatePicker.swift.
- [x] T004 [US2] Prove legacy disabled filtering, persistent reference counts and review journal regressions with XCTest.
- [x] T005 [US2] Extend LessonBook.swift with observable provenance, usage and bounded review status; integrate RunSession.swift and AgentLoop.swift.
- [x] T006 [US2] Expose real ExperienceStore entries and add native LearningView.swift linked from HomeView.swift, SettingsView.swift and PrivacyViews.swift; localize labels.
- [x] T007 [US3] Add per-lesson disable/delete and clear controls with late-review protection; test persistence and retrieval exclusions.
- [ ] T008 Run complete device build, simulator suite and workflow policy tests on exact final SHA; repair actual failures.
- [ ] T009 Converge spec/plan/tasks against implementation, review the changes, update project checkpoints and draft PR.
- [ ] T010 Verify artifact build/version/hash and deliver build75 unsigned IPA on E:/桌面; state physical-phone validation limits.

Dependencies: T002 before T003; T004 before T005; T005 before T006/T007; T008 after all implementation; T009/T010 after passing verification. Work is sequential in this session; no automatic sub-agent delegation.
