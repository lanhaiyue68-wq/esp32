"""pulldiag.py <out>: pull Documents/diagnostics (read only)."""
import asyncio, os, sys
from pymobiledevice3.lockdown import create_using_usbmux
from pymobiledevice3.services.house_arrest import HouseArrestService
async def main():
    os.makedirs(sys.argv[1], exist_ok=True)
    afc = await HouseArrestService.create(await create_using_usbmux(), "com.example.esp32agent", documents_only=True)
    names = sorted(n for n in await afc.listdir("/Documents/diagnostics") if n not in (".", ".."))
    print(names)
    for n in names:
        await afc.pull(f"/Documents/diagnostics/{n}", sys.argv[1], progress_bar=False)
asyncio.run(main())
