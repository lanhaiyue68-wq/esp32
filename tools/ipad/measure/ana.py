import sys, json, numpy as np
from PIL import Image
d, step = sys.argv[1], sys.argv[2]
moves = json.load(open(f"{d}/{step}.json"))
fr = [np.asarray(Image.open(f"{d}/{step}_{i:02d}.jpg").convert("L"), dtype=np.int16) for i in range(len(moves) + 1)]
bg = np.median(np.stack(fr), axis=0)
pos = []
for f in fr:
    m = (bg - f) > 45
    m[:40, :] = False  # status bar clock
    ys, xs = np.nonzero(m)
    pos.append((xs.mean(), ys.mean(), len(xs)) if len(xs) > 30 else None)
print("frame", fr[0].shape)
for mv, a, b in zip(moves, pos, pos[1:]):
    if a and b:
        px, py = b[0] - a[0], b[1] - a[1]
        L = (mv["dx"]**2 + mv["dy"]**2) ** .5
        moved = (px**2 + py**2) ** .5
        print(f'{mv["i"]:2d} {mv.get("kind","m")} send ({mv["dx"]:5d},{mv["dy"]:5d}) L={L:5.0f} -> px ({px:6.1f},{py:6.1f}) |{moved:6.1f}| px/unit {moved/L:.3f}  at ({b[0]:.0f},{b[1]:.0f}) n={b[2]} {mv["ms"]}ms')
    else:
        print(mv["i"], "pointer not found", a and a[2], b and b[2])
