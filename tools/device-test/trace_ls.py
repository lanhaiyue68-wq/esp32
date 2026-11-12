"""List Lan Agent trace folders on the phone between two local times, or pull named files of one (read only).
Usage: trace_ls.py list 152500 154000      |  trace_ls.py pull <folder> <out_dir> [file ...]
"""
import asyncio, os, sys
from pymobiledevice3.lockdown import create_using_usbmux
from pymobiledevice3.services.house_arrest import HouseArrestService


async def main():
    lockdown = await create_using_usbmux()
    afc = await HouseArrestService.create(lockdown, "com.example.esp32agent", documents_only=True)
    if sys.argv[1] == "list":
        a, b = sys.argv[2], sys.argv[3]
        for n in sorted(await afc.listdir("/Documents/traces")):
            if n.startswith("20261108-") and a <= n[9:15] <= b:
                files = [f for f in await afc.listdir(f"/Documents/traces/{n}") if f not in (".", "..")]
                print(n, len(files), sorted(files)[:6])
    else:
        folder, out = sys.argv[2], sys.argv[3]
        os.makedirs(out, exist_ok=True)
        for f in sys.argv[4:]:
            await afc.pull(f"/Documents/traces/{folder}/{f}", out, progress_bar=False)
        print("pulled", len(sys.argv) - 4)


asyncio.run(main())
