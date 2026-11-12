"""tl121.py <prefix e.g. 20261111-08>: list trace folders on the phone starting with the prefix (read only)."""
import asyncio, sys
from pymobiledevice3.lockdown import create_using_usbmux
from pymobiledevice3.services.house_arrest import HouseArrestService


async def main():
    afc = await HouseArrestService.create(await create_using_usbmux(), "com.example.esp32agent", documents_only=True)
    for n in sorted(await afc.listdir("/Documents/traces")):
        if n.startswith(sys.argv[1]):
            files = [f for f in await afc.listdir(f"/Documents/traces/{n}") if f not in (".", "..")]
            print(n, len(files), sorted(files)[:8])


asyncio.run(main())
