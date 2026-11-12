"""pulllog.py <out>: pull only debug.log (read only)."""
import asyncio, os, sys
from pymobiledevice3.lockdown import create_using_usbmux
from pymobiledevice3.services.house_arrest import HouseArrestService
async def main():
    os.makedirs(sys.argv[1], exist_ok=True)
    afc = await HouseArrestService.create(await create_using_usbmux(), "com.example.esp32agent", documents_only=True)
    print([n for n in await afc.listdir("/Documents") if n not in (".", "..")])
    await afc.pull("/Documents/debug.1.log", sys.argv[1], progress_bar=False)
    names = sorted(n for n in await afc.listdir("/Documents/traces") if n.startswith("20261110-"))
    print(names[-20:])
asyncio.run(main())
