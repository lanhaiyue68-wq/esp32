# Build79: deterministic pointer motion

The user's build78 screenshot stops after sampling with 2.1% residual. Logs40 confirms six sampling attempts, each rejected before fresh validation. Identical `(140,265)` commands in four rounds landed at x=0.448–0.499 and y=0.449–0.484. The `(75,75)` command was stable across six rounds. This rules out treating every deviation as a fixed coordinate offset or merely increasing the acceptance threshold.

Retained board metrics report firmware v34, `curve=true`, `curve_rev=20`. The matching local v34 firmware implements `move` through randomized Bezier reports whenever that stored switch is on, including axis-only moves. Build78 never queried or changed that switch. Separating axes therefore did not establish a deterministic report path. Host pointer acceleration can convert different curved report sequences into different screen endpoints despite equal count totals.

Build79 queries `curve` before each mapped gesture's home. An enabled board must acknowledge `curve off` before positioning proceeds. Already-disabled boards are queried without repeated NVS writes. Only an explicit unsupported-command response permits legacy straight firmware; timeouts and unexpected replies stop positioning. Calibration and normal mapped positioning share this path. The existing firmware setting is used over the current connection; there is no firmware update or USB requirement.

Build78 parameters require remeasurement because their movement mode was unverified. Initial sampling is reduced to two rough and five spread-out measurements, followed by four fresh validation taps (11 normally). A single refinement adds four checks only when needed; the progress total reflects that decision. The 1.5% acceptance limit and save-after-validation behavior remain.

## Verification

The Foundation-only harness extracts the actual production `ProbeMotion` enum. On pre-fix commit `7afd9b9`, eight firmware-contract tests ran: seven failed, with ten assertion failures. They reproduce the missing mode check, varying repeated landings, failure to recheck a reset board, and motion continuing after an unconfirmed setting or timeout. The unsupported legacy-firmware case passed.

Final Release build, simulator suite and package verification are pending. There is no attached physical phone; CI cannot establish real iPhone landing accuracy. Raw diagnostic files remain local outside Git.
