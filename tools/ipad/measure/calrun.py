import asyncio, sys, time, re
sys.path.insert(0, r"E:\AgentStorage\esp32\iphone-agent-build13\tools\ipad")
import lan_usb_ipad as L
async def aw(x):
    return await x if asyncio.iscoroutine(x) else x
async def log():
    a = await aw(L.afc())
    return (await aw(a.get_file_contents("/Documents/debug.log"))).decode("utf-8", "replace").splitlines()
async def main():
    before = len(await log())
    print(await aw(L.call("POST", "/calibrate", {})))
    t0 = time.time()
    while time.time() - t0 < 150:
        await asyncio.sleep(5)
        lines = (await log())[before:]
        if any(re.search(r"calibration: ±|calibration failed|calibration: pointer not found", l) for l in lines):
            break
    keep = re.compile(r"screen is about|probe|calibration|arrive|tap \(|ipad home|cmd .*(stroke|move -|move \d)")
    for l in lines:
        if keep.search(l):
            print(l[11:23], l[25:200])
    print("elapsed", round(time.time() - t0))
asyncio.run(main())
