"""abstats.py <all.log> <abruns.jsonl>: per A/B run, taps / corrected / loose (no correction because inside the target),
time from first look to click, and total HID time from the step timing lines."""
import json, re, sys
from datetime import datetime

arrive = re.compile(r'^(\S+) arrive \(([\d.]+), ([\d.]+)\): seen at \(([\d.]+), ([\d.]+)\)(.*)$')
click = re.compile(r'^(\S+) cmd #\d+ click ')
timing = re.compile(r'^(\S+) step \d+ timing: frame (\d+) ms, LLM (\d+) ms, HID (\d+) ms')

def t(s):
    return datetime.strptime(s[:19], '%Y-%m-%dT%H:%M:%S').timestamp() + float('0' + s[19:23])

lines = open(sys.argv[1], encoding='utf-8', errors='replace').read().splitlines()
runs = [json.loads(l) for l in open(sys.argv[2], encoding='utf-8')]
res = json.load(open(sys.argv[3], encoding='utf-8')) if len(sys.argv) > 3 else {}
tot = {}
for r in runs:
    a, b = t(r['start'] + '.000Z'), t(r['end'] + '.000Z')
    taps, cur, frame, llm, hid = [], None, 0, 0, 0
    for line in lines:
        if not line[:4].isdigit():
            continue
        try:
            ts = t(line[:24])
        except ValueError:
            continue
        if ts < a or ts > b:
            continue
        m = arrive.match(line)
        if m:
            tx, ty = float(m.group(2)), float(m.group(3))
            if cur is None or (tx, ty) != cur['target']:
                cur = {'target': (tx, ty), 'start': ts, 'corr': 0, 'loose': False}
            if 'correcting' in m.group(6):
                cur['corr'] += 1
            if 'inside the target' in m.group(6):
                cur['loose'] = True
            continue
        m = click.match(line)
        if m and cur is not None:
            cur['spent'] = ts - cur['start']
            taps.append(cur)
            cur = None
            continue
        m = timing.match(line)
        if m:
            frame += int(m.group(2)); llm += int(m.group(3)); hid += int(m.group(4))
    n = len(taps); c = sum(1 for x in taps if x['corr']); lo = sum(1 for x in taps if x['loose'])
    sp = sum(x['spent'] for x in taps)
    k = r['mode']
    d = tot.setdefault(k, dict(n=0, c=0, lo=0, sp=0.0, hid=0, llm=0, frame=0, secs=0))
    for key, v in (('n', n), ('c', c), ('lo', lo), ('sp', sp), ('hid', hid), ('llm', llm), ('frame', frame), ('secs', b - a)):
        d[key] += v
    print(f"{r['id'][:22]:22} {k:3} {b - a:5.0f}s taps {n:3} corrected {c:3} loose {lo:2} look->click {sp:5.0f}s "
          f"({sp / max(n, 1):.1f}/tap)  HID {hid / 1000:5.0f}s LLM {llm / 1000:5.0f}s frame {frame / 1000:4.0f}s")
print()
for k, d in tot.items():
    print(f"{k:3} total {d['secs']:5.0f}s taps {d['n']} corrected {d['c']} ({100 * d['c'] / max(d['n'], 1):.0f}%) loose {d['lo']} "
          f"look->click {d['sp']:.0f}s ({d['sp'] / max(d['n'], 1):.2f}/tap) HID {d['hid'] / 1000:.0f}s LLM {d['llm'] / 1000:.0f}s frame {d['frame'] / 1000:.0f}s")
