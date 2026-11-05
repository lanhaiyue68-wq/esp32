# Learned routes and lesson cleanup (build85)

User report 2026-11-05: no learning was felt across runs. Lessons (LessonBook) only add advice to the prompt and
ExperienceStore deliberately never keeps successes, so every run still asks the model at every step (~2 s each, logs46).
Logs43–46 also showed every WeChat check receiving an unrelated lesson ("先选择中间三个按钮的左边那个…") and several
contradicting "don't" rules with coordinates.

## RouteBook (Services/RouteBook.swift)

- After a run that ends `done`, the navigation up to the first typing (tap, swipe, Home, Back) is kept with each
  step's coarse screen signature (Vision.experienceScene) and, for a tap, the text label under it
  (CandidatePicker.label). Dead taps and detours (a later step on the same screen) are dropped. A tap on 发送/付款/
  转账/删除/… ends the route. At most 12 steps, 64 routes, 30 days. Stored locally in routes-v1.json.
- Before a run, a route matches when the task is similar (bigram Jaccard ≥ 0.5), the start screen matches, and every
  label the old task named (an app or chat) is named by the new task too (Claude ≠ ChatGPT, 蓝海乐 ≠ 测试群).
- AgentLoop.replay walks it without the model: each screen must match the learned one, a labelled tap goes to the
  label where it is now, and a step that changes nothing stops it. The model continues from there with the replayed
  steps in its recent actions; it still confirms the result. Replay never types, sends or draws.
- Three misses without more successes drop a route. The learning switch and "Clear all learning records" cover routes.

## Lessons

- Matching also requires bigram Jaccard ≥ 0.2, so a short task sharing "打开/微信" with the long watch prompt no
  longer matches; similar wordings (打开白板画一个笑脸 / 打开无边记画个笑脸) still do.
- Self-learned lessons naming coordinates are not kept, and the reflection prompt asks for controls by name.
- Build85 drops all self-learned lessons once (UserDefaults selfLessonsReset85); the user's own corrections stay.

Not verified on a phone: replay timing, label recognition on real screens, and how often routes match in practice.
