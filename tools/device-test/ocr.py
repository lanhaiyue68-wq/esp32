import asyncio, json, sys, os
sys.path.insert(0, r"D:\AIProjects\agent-toolbox\iphone-logs")
from lan_usb import call
async def main():
    code, body = await call("GET", "/ocr", timeout=30)
    d = json.loads(body)
    sys.stdout.reconfigure(encoding="utf-8")
    print({k: d[k] for k in ("home", "search", "keyboard")})
    out = []
    for row in d["rows"]:
        for p in row:
            t, pos = p.rsplit(" @", 1)
            xy = pos.split(" ")[0]
            out.append(f"{t}@{xy}")
    print(" | ".join(out))
asyncio.run(main())
