"""trace_pull.py <prefix> [out]: list /Documents/traces folders starting with <prefix> (phone local time, e.g. 20261113-08); with out, pull the first one's steps.jsonl. Run with the pymobiledevice3 python."""
import asyncio, sys, json, os
from pymobiledevice3.lockdown import create_using_usbmux
from pymobiledevice3.services.house_arrest import HouseArrestService
async def m():
    afc = await HouseArrestService.create(await create_using_usbmux(), 'com.example.esp32agent', documents_only=True)
    names = sorted(n for n in await afc.listdir('/Documents/traces') if n.startswith(sys.argv[1]))
    print(names)
    if len(sys.argv) > 2 and names:
        out = sys.argv[2]; os.makedirs(out, exist_ok=True)
        await afc.pull(f'/Documents/traces/{names[0]}/steps.jsonl', out, progress_bar=False)
asyncio.run(m())
