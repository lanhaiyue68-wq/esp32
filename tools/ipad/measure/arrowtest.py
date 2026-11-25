import sys, json, numpy as np
from PIL import Image
sys.path.insert(0, sys.argv[1]); from arrow import arrow
d, tag = sys.argv[2], sys.argv[3]
mv = json.load(open(f"{d}/{tag}.json"))
fr = [np.asarray(Image.open(f"{d}/{tag}_{i:02d}.jpg").convert("L")) for i in range(len(mv) + 1)]
bg = np.median(np.stack([f.astype(int) for f in fr]), axis=0)
def cen(f):
    m = (bg - f) > 45; m[:77] = False; ys, xs = np.nonzero(m)
    return (xs.mean() / f.shape[1], ys.mean() / f.shape[0]) if 30 < len(xs) < 600 else None
for i in range(1, len(fr)):
    c = cen(fr[i]); r = arrow(fr[i - 1], fr[i], c if c else (0.5, 0.5))
    print(i, mv[i-1]["kind"], mv[i-1]["dx"], mv[i-1]["dy"], "centroid", None if not c else (round(c[0]*960), round(c[1]*1280)), "tip", None if not r else (round(r[0]*960), round(r[1]*1280), r[2]))
