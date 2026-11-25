import asyncio, sys, time
sys.path.insert(0, r"E:\AgentStorage\esp32\iphone-agent-build13\tools\ipad")
import lan_usb_ipad as L
async def aw(x): return await x if asyncio.iscoroutine(x) else x
async def main():
    t = time.time(); out = []
    for c in [x.strip() for a in sys.argv[1:] for x in a.split(";") if x.strip()]:
        if c.startswith("sleep"):
            await asyncio.sleep(float(c.split()[1])); continue
        r = await aw(L.call("POST", "/board", {"cmd": c})); out.append((c, round((time.time() - t) * 1000)))
    print(out)
asyncio.run(main())
