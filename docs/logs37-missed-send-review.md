# logs37: a click acknowledgement is not a completed send

## Evidence

The export was produced by build 75 on iOS 27.0.1. The direct display stream was live. At 23:46:16 UTC the local field check accepted the requested input; at 23:46:23 the actor requested tap (908,543). The board acknowledged home, move (255,334), and click. There was no visual pointer aim. The run then entered read-only send verification and failed at 23:46:42.

The actual Claude trace was absent: five later internal report/navigation runs occupied the entire five-run export window. The shared debug log retained the commands, but not the Claude frames. The Claude miss location therefore cannot be established from this export.

The included WeChat report provides a direct before/after comparison of the same defect. The report draft remained complete after tap (863,887). Its post-action frame shows the pointer at approximately (0.97,0.98), below and right of the intended keyboard send control. A later attempt at (863,886) used almost identical board units, landed near the control, and produced a new outgoing bubble. This is evidence of an unreliable open-loop landing, rather than a text-generation error.

## Broken contracts

1. A first send tap used the ordinary fast path. The board acknowledging a relative move established delivery of the command, not its screen endpoint.
2. Precision aiming could return without finding the pointer, lose it during correction, or exhaust corrections; the caller still clicked.
3. The send guard treated a successful HID command as a sent message. Recovery recognized extra letters, but a correct, unchanged draft could only wait until failure.
4. The export window selected the latest five internal runs rather than preserving the owner task within the existing bounded local history.
5. Pixel aiming observed the pointer before its probe, then assumed the inverse mouse move restored that point. A test using actual rendered pointer frames (without the finder shortcut) clicked at x=0.8848 when asked for x=0.863. Probe frames also used a time boundary before command acknowledgement.

## Bounded repair and validation

Regression tests were committed before implementation (`560788b`, `7f8e42d`). RED run40424580741 executed398 tests with11 expected assertions in six regression methods. RED run40425693931 executed401 tests with12 expected assertions, including the real pixel endpoint error. No unrelated regressions appeared. Raw CI output and phone evidence stay outside Git.

The repair must retain correct text, require visual aim for a pending message's send tap, refuse an unverified precision click, and permit only bounded recovery on positive evidence that the same draft remains with no new matching bubble. Unreadable/empty fields and new bubbles retain duplicate protection. The existing storage limits and wireless/direct capture architecture remain in force.

Build76 implementation is ready for full CI. It measures the returned pointer after acknowledged probe movements, refuses an unverified precision click, aims the first send tap, and preserves the raw expected draft for exact inspection. Recovery requires two post-action observations of that same complete field and no new matching message, with at most two recoveries. Empty/unreadable fields retain protection. The export includes up to20 retained runs, within the existing20MB payload and80MB local budgets, excluding video.

Physical-phone success is not claimed by these simulated tests. Original phone data remains outside Git.
