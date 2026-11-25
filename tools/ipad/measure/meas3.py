import asyncio, sys, json, time, math, random
sys.path.insert(0, r"E:\AgentStorage\esp32\iphone-agent-build13\tools\ipad")
import lan_usb_ipad as L
out, tag = sys.argv[1], sys.argv[2]
plan = json.loads(sys.argv[3])  # [[kind, dx, dy, side], ...] kind: "m" straight, "c" curve
async def aw(x): return await x if asyncio.iscoroutine(x) else x
async def frame(path):
    st, data = await aw(L.call("GET", "/frame")); open(path, "wb").write(data)
async def board(cmd): return await aw(L.call("POST", "/board", {"cmd": cmd}))
def curve(dx, dy, side, bow=0.14, n=24):
    ln = math.hypot(dx, dy); ux, uy = dx / ln, dy / ln; nx, ny = -uy * side * bow * ln, ux * side * bow * ln
    c1 = (dx * 0.3 + nx, dy * 0.3 + ny); c2 = (dx * 0.7 + nx, dy * 0.7 + ny)
    pts, last = [], (0, 0)
    for i in range(1, n + 1):
        t = i / n; u = 1 - t
        bx = 3*u*u*t*c1[0] + 3*u*t*t*c2[0] + t**3*dx; by = 3*u*u*t*c1[1] + 3*u*t*t*c2[1] + t**3*dy
        q = (dx, dy) if i == n else (round(bx), round(by))
        pts.append(f"{q[0]-last[0]} {q[1]-last[1]}"); last = q
    return "stroke " + " ".join(pts)
async def main():
    for c in ("round on", "coex bt", "step 60", "pace 30"): await board(c)
    log = []
    await asyncio.sleep(0.6); await frame(f"{out}/{tag}_00.jpg")
    for i, (kind, dx, dy, side) in enumerate(plan, 1):
        cmd = f"move {dx} {dy}" if kind == "m" else curve(dx, dy, side)
        t = time.time(); r = await board(cmd); ms = round((time.time() - t) * 1000)
        await asyncio.sleep(0.6); await frame(f"{out}/{tag}_{i:02d}.jpg")
        log.append({"i": i, "dx": dx, "dy": dy, "ms": ms, "kind": kind})
    json.dump(log, open(f"{out}/{tag}.json", "w"))
asyncio.run(main())
