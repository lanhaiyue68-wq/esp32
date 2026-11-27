"""Pull Echo's model runs (Documents/traces/<yyyyMMdd-HHmmss>/: steps.jsonl and the frames each step was decided on)
to this computer, to write those orders into fixed steps (192, B14: the model learns an order first).
Usage: pull_traces.py <tools/ipad dir> <out dir> [since yyyyMMdd-HHmmss]
Prints each run: its task's first line, its steps (action, target, x/y, text) — the frames are saved beside."""
import asyncio
import json
import os
import sys

sys.path.insert(0, sys.argv[1])
import lan_usb_ipad as m  # noqa: E402

out = sys.argv[2]
since = sys.argv[3] if len(sys.argv) > 3 else ""


async def go():
    afc = await m.afc()
    if not await afc.exists("/Documents/traces"):
        print("no runs yet (Documents/traces not made)")
        return
    runs = sorted(r for r in await afc.listdir("/Documents/traces") if r.replace("imported-", "") >= since)
    for run in runs:
        folder = f"/Documents/traces/{run}"
        local = os.path.join(out, run)
        os.makedirs(local, exist_ok=True)
        for name in await afc.listdir(folder):
            path = f"{folder}/{name}"
            if await afc.isdir(path):
                continue
            with open(os.path.join(local, name), "wb") as f:
                f.write(await afc.get_file_contents(path))
        steps = os.path.join(local, "steps.jsonl")
        if not os.path.exists(steps):
            continue
        print(f"== {run}")
        for line in open(steps, encoding="utf-8"):
            rec = json.loads(line)
            if rec.get("kind") == "task":
                print("  task:", rec.get("task", "").split("\n")[0][:120])
            elif rec.get("kind") == "step":
                keep = {k: v for k, v in rec.items() if k not in ("kind", "n", "t") and v not in ("", None)}
                print("  step:", json.dumps(keep, ensure_ascii=False)[:200])


asyncio.run(go())
