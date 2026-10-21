# Prompts

The model prompts the app sends, as plain text. They are bundled into the app at build time
(`ios/project.yml`, read by `ios/IPhoneAgent/Agent/Prompts.swift`).

- `planner.md`: writes a short plan from the goal and the first screen.
- `actor.md`: picks the next action(s) from each screenshot; lists the action syntax the app parses.
- `app-rules.md`: rules for running inside the phone (never touch this app, toggles, home screen icons); appended
  to both.

No Mac at hand: put an edited copy in the app's Documents folder (Files › On My iPhone › the app ›
`prompts/<name>.md`; it wins from the next app launch) or add rules to `Documents/rules.md` (every run). The
app also learns the user's Review notes by itself (`LessonBook`). Otherwise edit, rebuild, and compare runs in the app's Runs tab. Keep the action list in `actor.md` in sync with
`ios/IPhoneAgent/Agent/Actions.swift`. Each file's final newline is not part of the prompt.
