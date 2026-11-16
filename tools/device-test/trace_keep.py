"""trace_keep.py <out_dir> [prefix]: copy every trace folder's steps.jsonl from the phone that is not kept yet (read only).
The phone keeps only its last 20 runs; run this every few minutes during a long regression to keep the models' thoughts.
Run with the pymobiledevice3 python."""
import asyncio, os, sys
from pymobiledevice3.lockdown import create_using_usbmux
from pymobiledevice3.services.house_arrest import HouseArrestService


async def main():
    out, prefix = sys.argv[1], (sys.argv[2] if len(sys.argv) > 2 else "")
    afc = await HouseArrestService.create(await create_using_usbmux(), "com.example.esp32agent", documents_only=True)
    names = sorted(n for n in await afc.listdir("/Documents/traces") if n.startswith(prefix) and n not in (".", ".."))
    kept = 0
    for n in names[:-1]:  # the newest may still be running: taken next time
        dest = os.path.join(out, n)
        if os.path.exists(os.path.join(dest, "steps.jsonl")):
            continue
        os.makedirs(dest, exist_ok=True)
        try:
            await afc.pull(f"/Documents/traces/{n}/steps.jsonl", dest, progress_bar=False)
            kept += 1
        except Exception as e:  # a folder without steps (a run that never began)
            print(n, "skipped:", str(e)[:80])
    print("kept", kept, "of", len(names))


asyncio.run(main())
