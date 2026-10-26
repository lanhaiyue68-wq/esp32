# Data model

Lesson extends the existing Codable object with optional disabled, uses, lastRun and lastTask. Existing used date remains last reference time. Missing new fields decode to enabled/unreferenced. Automatic provenance remains auto/from; human notes remain higher priority.

ReviewEvent is Codable/Identifiable by source run, with task (max200 characters), timestamp, state (reviewing/learned/noLesson/skipped/failed/interrupted), fixed user-facing reason and retained count. Keep at most24 records under32KB. It contains no screenshot or credential/error dump. Clear removes events with lessons; disabled learning adds no task text. A stale review epoch cannot add lessons or overwrite a cleared journal.

Measured cases reuse existing bounded ExperienceStore entries; show verdict and operation, observations and date. Hashes and scenes are not a claim of a learned successful route.
