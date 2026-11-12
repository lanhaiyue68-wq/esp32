"""readlog_get.py <out>: pull the newest file(s) of /Documents/readlog (read only)."""
import asyncio, os, sys
from pymobiledevice3.lockdown import create_using_usbmux
from pymobiledevice3.services.house_arrest import HouseArrestService
async def main():
    out = sys.argv[1]; os.makedirs(out, exist_ok=True)
    afc = await HouseArrestService.create(await create_using_usbmux(), "com.example.esp32agent", documents_only=True)
    names = sorted(n for n in await afc.listdir("/Documents/readlog") if n not in (".", ".."))
    print("files", names[-5:])
    for n in names[-2:]:
        await afc.pull(f"/Documents/readlog/{n}", out, progress_bar=False)
asyncio.run(main())
