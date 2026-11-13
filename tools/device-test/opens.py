# opens.py <debug.log> <startUTC> <endUTC>: one line per app open: name, seconds, how its taps went
import re, sys
L = [l for l in open(sys.argv[1], encoding='utf-8', errors='replace') if sys.argv[2] <= l[:23] <= sys.argv[3]]
cur = None
from collections import Counter
agg = Counter()
for l in L:
    m = re.search(r"open (\S+): ([\d.]+) s$", l.strip())
    if m and cur:
        cur['s'] = float(m[2]); print(f"{cur['name']:6} {cur['s']:5.1f}s  {' | '.join(cur['ev'])}"); cur = None; continue
    m = re.search(r"open (\S+): (.*)$", l.strip())
    if m:
        if not cur: cur = {'name': m[1], 'ev': []}
        msg = m[2]
        short = {'the page in front': 'front', 'still on the Home Screen after the tap': 'MISS'}.get(msg, msg[:40])
        cur['ev'].append(short); agg[short] += 1; continue
    if cur:
        for pat, tag in [(r"hop \d+ from", 'hop'), (r"from the right border", 'rborder'), (r"from the bottom border", 'bborder'),
                         (r"arrive .*seen at .*after", 'seen+fix'), (r"arrive .*pointer not seen", 'notseen'),
                         (r"arrive .*seen at \([\d., ]+\)$", 'seen'), (r"aim .*(not found|lost)", 'aimlost'),
                         (r"keyboard: picked.*not reported", 'KBDFAIL')]:
            if re.search(pat, l.strip()): cur['ev'].append(tag); agg[tag] += 1; break
print(dict(agg))
