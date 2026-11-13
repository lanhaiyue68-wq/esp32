"""timing.py <debug.log> <start UTC ISO> <end UTC ISO>: where a run's time went (steps, LLM, HID, opens, Codex vs Doubao)."""
import re, sys
from collections import Counter

log, a, b = sys.argv[1], sys.argv[2], sys.argv[3]
L = [x for x in open(log, encoding="utf-8", errors="replace").read().splitlines() if a <= x[:24] < b]
f = l = h = n = 0
for x in L:
    m = re.search(r"timing: frame (\d+) ms, LLM (\d+) ms, HID (\d+) ms", x)
    if m:
        f += int(m[1]); l += int(m[2]); h += int(m[3]); n += 1
opens = [(m[1], float(m[2])) for m in (re.search(r"open (\S+): ([\d.]+) s", x) for x in L) if m]
calls = Counter(m[1] for m in (re.search(r"llm → (\S+):", x) for x in L) if m)
plus = sum("plus planner:" in x and "first token" in x for x in L)
plus_fail = sum("plus planner" in x and "rests" in x for x in L)
print(f"steps {n}: frame {f/1000:.0f}s, LLM {l/1000:.0f}s, HID {h/1000:.0f}s")
print(f"opens {len(opens)}: {sum(t for _, t in opens):.0f}s, avg {sum(t for _, t in opens)/max(1,len(opens)):.1f}s;",
      " ".join(f"{a}:{t:.0f}" for a, t in opens))
print(f"doubao calls {sum(v for k, v in calls.items() if 'doubao' in k)}, plus answers {plus}, plus failures {plus_fail}")
for k in ["stale plan", "replan (stuck)", "planner drives", "too far to trust", "aim (", "refused", "part done",
          "the thought says it is finished", "stall: the main", "thermal"]:
    c = sum(k in x for x in L)
    if c:
        print(f"  {k}: {c}")
th = [re.search(r"thermal (\w+)", x)[1] for x in L if re.search(r"thermal (\w+)", x)]
if th:
    print("  thermal:", Counter(th).most_common())
