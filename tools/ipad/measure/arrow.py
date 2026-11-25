import numpy as np
TOP = 0.06
def arrows(a, b, near, window=0.25, threshold=40):
    h, w = a.shape
    x0 = max(0, int((near[0] - window) * w)); x1 = min(w - 1, int((near[0] + window) * w))
    y0 = max(int(TOP * h), int((near[1] - window) * h)); y1 = min(h - 1, int((near[1] + window) * h))
    if x1 <= x0 or y1 <= y0: return []
    d = np.abs(a[y0:y1+1, x0:x1+1].astype(int) - b[y0:y1+1, x0:x1+1].astype(int)) > threshold
    ys, xs = np.nonzero(d); xs = xs + x0; ys = ys + y0
    if len(xs) == 0 or len(xs) >= w * h // 50: return []
    cell = max(4, w // 40); s = (w * w) / (960 * 960)
    look, reach, most = 1.2 * cell, 0.75 * cell, 1.2 * cell
    rem = list(zip(xs.tolist(), ys.tolist())); tips = []
    for _ in range(4):
        if not rem: break
        cnt = {}
        for x, y in rem: k = ((y - y0) // cell) * 100000 + (x - x0) // cell; cnt[k] = cnt.get(k, 0) + 1
        k = max(cnt, key=cnt.get)
        gx = x0 + (k % 100000) * cell + cell / 2; gy = y0 + (k // 100000) * cell + cell / 2
        sel = [(x, y) for x, y in rem if (x - gx) ** 2 + (y - gy) ** 2 <= look * look]
        cx = sum(p[0] for p in sel) / len(sel) if sel else gx; cy = sum(p[1] for p in sel) / len(sel) if sel else gy
        patch = [(x, y) for x, y in rem if (x - cx) ** 2 + (y - cy) ** 2 <= reach * reach]
        rem = [(x, y) for x, y in rem if (x - cx) ** 2 + (y - cy) ** 2 > reach * reach]
        if not patch: continue
        mx = [p[0] for p in patch]; my = [p[1] for p in patch]; n = len(patch)
        if 60 * s <= n <= 600 * s and max(mx) - min(mx) <= most and max(my) - min(my) <= most:
            t = min(patch, key=lambda p: p[0] + p[1]); tips.append((t[0] / w, t[1] / h, n))
    return tips
def arrow(a, b, near, window=0.25):
    t = arrows(a, b, near, window)
    return min(t, key=lambda p: (p[0] - near[0]) ** 2 + (p[1] - near[1]) ** 2) if t else None
