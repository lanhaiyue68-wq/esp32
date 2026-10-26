# Research and decisions

- Reuse LessonBook and ExperienceStore: their current retrieval reaches planner/actor requests; a separate fake learning store would misrepresent behavior.
- Use existing exact paste hop for multiline/unsupported input: the board has US keys, and sending newline as Enter can submit partial code. Pinyin cannot represent emoji, Arabic or kana.
- Keep automatic route summaries limited to eligible completed runs. Failed tasks retain measured uncertainty, not guessed successful routes. Display why a review did not produce a lesson.
- Persist optional usage metadata in the existing array and review events in a small sidecar to preserve old data compatibility. No model-weight training or extra recurring inference.
- Use standard SwiftUI lists/details/navigation. No web UI, third-party UI library or new dependency is needed. No user clarification blocks this bounded implementation.
