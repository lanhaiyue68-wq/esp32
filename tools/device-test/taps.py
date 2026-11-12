"""taps.py <debug.log>...: for every tap the pointer was seen for, where it first stopped (a tap with no correction
would land there), how many corrections followed and how long they took until the click."""
import re, sys
from datetime import datetime

arrive = re.compile(r'^(\S+) arrive \(([\d.]+), ([\d.]+)\): seen at \(([\d.]+), ([\d.]+)\)(.*)$')
click = re.compile(r'^(\S+) cmd #\d+ click ')

def t(s):
    return datetime.strptime(s[:23], '%Y-%m-%dT%H:%M:%S.%f').timestamp()

taps = []
for path in sys.argv[1:]:
    cur = None
    for line in open(path, encoding='utf-8', errors='replace'):
        line = line.rstrip('\n')
        m = arrive.match(line)
        if m:
            ts, tx, ty, sx, sy, rest = m.groups()
            tx, ty, sx, sy = map(float, (tx, ty, sx, sy))
            if cur is None or (tx, ty) != cur['target']:
                cur = {'target': (tx, ty), 'first': (sx, sy), 'start': t(ts), 'corr': 0, 'final': (sx, sy)}
            cur['final'] = (sx, sy)
            if 'correcting' in rest:
                cur['corr'] += 1
            continue
        m = click.match(line)
        if m and cur is not None:
            cur['click'] = t(m.group(1))
            taps.append(cur)
            cur = None

def err(a, b):
    return abs(a[0] - b[0]), abs(a[1] - b[1])

n = len(taps)
corrected = [x for x in taps if x['corr'] > 0]
print(f'taps seen: {n}; corrected: {len(corrected)} ({100 * len(corrected) / max(n, 1):.0f}%)')
spent = [x['click'] - x['start'] for x in corrected]
print(f'time from first look to click, corrected taps: total {sum(spent):.0f} s, mean {sum(spent) / max(len(spent), 1):.1f} s')
plain = [x['click'] - x['start'] for x in taps if x['corr'] == 0]
print(f'same, taps needing no correction: mean {sum(plain) / max(len(plain), 1):.2f} s')
# Would a tap with no correction have hit? Big targets: a chat-list row (+-0.035 in y, wide), the input box (+-0.025 y,
# +-0.25 x), the back arrow (+-0.03). Small: a toggle or a small icon (+-0.015).
for name, hx, hy in [('small (+-1.5%)', 0.015, 0.015), ('back arrow (+-3%)', 0.03, 0.03), ('input box (+-25% x, +-2.5% y)', 0.25, 0.025), ('list row (+-35% x, +-3.5% y)', 0.35, 0.035)]:
    hit = sum(1 for x in taps if err(x['first'], x['target'])[0] <= hx and err(x['first'], x['target'])[1] <= hy)
    print(f'first stop inside a {name} target: {hit}/{n} ({100 * hit / max(n, 1):.0f}%)')
big = [x for x in corrected if err(x['first'], x['target'])[0] <= 0.25 and err(x['first'], x['target'])[1] <= 0.025]
saved = sum(x['click'] - x['start'] for x in big)
print(f'corrected taps whose first stop was already inside an input-box-sized target: {len(big)}; their correction time {saved:.0f} s')
ex = sorted(err(x['first'], x['target'])[0] for x in taps)
ey = sorted(err(x['first'], x['target'])[1] for x in taps)
q = lambda v, p: v[min(len(v) - 1, int(p * len(v)))] if v else 0
print(f'first-stop error x: median {q(ex, .5):.3f}, 90% {q(ex, .9):.3f}; y: median {q(ey, .5):.3f}, 90% {q(ey, .9):.3f}')
