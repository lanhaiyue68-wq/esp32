"""Drive Lan Agent on the USB-connected iPhone through its test channel (build 106+). Needs: the phone trusted, the Apple
Mobile Device Service running, the app open at least once. The token is random, kept next to this script (never printed)
and in the app's Documents; `disarm` removes both, after which the app refuses everything.

Usage: lan_usb.cmd arm | disarm | status | frame <out.jpg> | steps [from] | run "<task>" [hint ...] | stop | share
       lan_usb.cmd g '{"do":"tap","x":0.5,"y":0.5}' | board <command> | watch on|off | release
"""
import asyncio
import json
import os
import secrets
import socket
import sys

from pymobiledevice3.lockdown import create_using_usbmux
from pymobiledevice3.services.house_arrest import HouseArrestService
from pymobiledevice3.usbmux import select_device

BUNDLE = os.environ.get("LAN_BUNDLE", "com.example.esp32agent.xiaolan.67AUY82AXY")  # 小藍 as 爱思 signed it (11-25)
PORT = 47821
TOKEN_FILE = os.path.join(os.path.dirname(os.path.abspath(__file__)), ".lan_usb_token")
REMOTE = "/Documents/testchannel.token"


async def afc():
    return await HouseArrestService.create(await create_using_usbmux(), BUNDLE, documents_only=True)


async def arm():
    token = secrets.token_hex(16)
    await (await afc()).set_file_contents(REMOTE, token.encode())
    with open(TOKEN_FILE, "w", encoding="ascii") as f:
        f.write(token)
    print("armed")


async def disarm():
    await (await afc()).rm(REMOTE)
    if os.path.exists(TOKEN_FILE):
        os.remove(TOKEN_FILE)
    print("disarmed")


async def call(method, path, body=None, timeout=600):
    device = await select_device()
    if device is None:
        raise SystemExit("no phone over USB: replug it, unlock it, tap Trust")
    sock = await device.connect(PORT)
    token = open(TOKEN_FILE, encoding="ascii").read().strip()
    data = json.dumps(body, ensure_ascii=False).encode() if body is not None else b""
    head = f"{method} {path} HTTP/1.1\r\nHost: phone\r\nX-Token: {token}\r\nContent-Length: {len(data)}\r\n\r\n".encode()
    sock.setblocking(True)
    sock.settimeout(timeout)
    sock.sendall(head + data)
    raw = b""
    try:
        while True:
            chunk = sock.recv(1 << 16)
            if not chunk:
                break
            raw += chunk
    except socket.timeout:
        pass
    finally:
        sock.close()
    header, _, payload = raw.partition(b"\r\n\r\n")
    status = int(header.split(b" ")[1]) if header else 0
    return status, payload


def show(status, payload):
    text = payload.decode("utf-8", "replace")
    sys.stdout.reconfigure(encoding="utf-8")
    print(text if status == 200 else f"HTTP {status}: {text}")
    return 0 if status == 200 else 1


async def main():
    if len(sys.argv) < 2:
        raise SystemExit(__doc__)
    what, rest = sys.argv[1], sys.argv[2:]
    if what == "arm":
        return await arm()
    if what == "disarm":
        return await disarm()
    if what == "status":
        return show(*await call("GET", "/status"))
    if what == "frame":
        status, payload = await call("GET", "/frame")
        if status != 200:
            return show(status, payload)
        with open(rest[0], "wb") as f:
            f.write(payload)
        print(f"{rest[0]} ({len(payload)} bytes)")
        return 0
    if what == "steps":
        return show(*await call("GET", f"/steps?from={rest[0] if rest else 0}"))
    if what == "run":
        return show(*await call("POST", "/run", {"task": rest[0], "hints": rest[1:]}))
    if what in ("stop", "share", "release"):
        return show(*await call("POST", f"/{what}", {}))
    if what == "g":
        return show(*await call("POST", "/gesture", json.loads(rest[0])))
    if what == "board":
        return show(*await call("POST", "/board", {"cmd": " ".join(rest)}))
    if what == "watch":
        return show(*await call("POST", "/watch", {"on": rest[0] == "on"}))
    if what == "servers":  # build 169+: servers '{"serverOn":true,"serverURL":"http://192.168.3.79:18971/zwt",...}'
        return show(*await call("POST", "/servers", json.loads(rest[0]) if rest else {}))
    raise SystemExit(__doc__)


if __name__ == "__main__":
    raise SystemExit(asyncio.run(main()) or 0)
