"""watchmon.py <since UTC HH:MM:SS> <minutes>: every 20 s pull the phone's debug.log (read only) and keep the watch's lines
since the given time in watchmon.txt (what was read, decided, sent, timings), so the watch test can be followed."""
import asyncio, os, re, sys, tempfile, time
from pymobiledevice3.lockdown import create_using_usbmux
from pymobiledevice3.services.house_arrest import HouseArrestService

since, minutes = sys.argv[1], float(sys.argv[2])
out = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'watchmon.txt')
keep = re.compile(r'watch|act \d+: (done|fail|type|open)|finished|sent|reply|look|tool|listen|plus planner')


async def pull(tmp):
    afc = await HouseArrestService.create(await create_using_usbmux(), "com.example.esp32agent", documents_only=True)
    await afc.pull("/Documents/debug.log", tmp, progress_bar=False)


async def main():
    end = time.time() + minutes * 60
    tmp = tempfile.mkdtemp()
    while time.time() < end:
        try:
            await pull(tmp)
            lines = open(os.path.join(tmp, 'debug.log'), encoding='utf-8', errors='replace').read().splitlines()
            today = [l for l in lines if len(l) > 20 and l[11:19] >= since and keep.search(l)
                     and 'capture: direct' not in l and 'check (screen changed)' not in l and 'no red mark' not in l
                     and 'timing: check' not in l]
            open(out, 'w', encoding='utf-8').write('\n'.join(l[11:23] + ' ' + l[24:260] for l in today) + '\n')
        except Exception as e:
            open(out, 'a', encoding='utf-8').write(f'pull failed: {e}\n')
        await asyncio.sleep(20)

asyncio.run(main())
