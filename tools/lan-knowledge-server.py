"""Lan Agent knowledge server: serves the .md / .txt files of ONE folder to the iPhone app, behind a password.

The app's WeChat watch (Knowledge Base > My computer) lists the files here and fetches only the ones switched on.
Nothing outside the folder is ever served. Standard library only.

Run (Windows):  py -3.12 tools\\lan-knowledge-server.py --dir "E:\\桌面\\小蓝知识库"
Defaults: the folder ChatTool writes its digests to (E:\\桌面\\小蓝知识库), port 8882, every network interface.
The password is made once and kept in <folder>\\.lan-agent-token; it is printed at start with this computer's
LAN addresses. Type both into the app.

GET /files?token=T                      {"files": [{"name": "营业.md", "chars": 120}, ...]}
GET /content?token=T&names=a.md%0Ab.md  {"text": "## a.md\\n...", "truncated": false}
"""
from __future__ import annotations

import argparse
import hmac
import json
import secrets
import socket
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import parse_qs, urlparse

SUFFIXES = {".md", ".txt"}
DEFAULT_DIR = Path(r"E:\桌面\小蓝知识库")


def load_token(folder: Path) -> str:
    path = folder / ".lan-agent-token"
    if path.exists() and path.read_text(encoding="utf-8").strip():
        return path.read_text(encoding="utf-8").strip()
    token = secrets.token_urlsafe(9)
    path.write_text(token, encoding="utf-8")
    return token


def list_files(folder: Path) -> list[dict]:
    """Files in the folder and one level of subfolders, names relative with "/"; hidden files skipped."""
    out = []
    for path in sorted(folder.glob("*")) + sorted(folder.glob("*/*")):
        rel = path.relative_to(folder)
        if path.is_file() and path.suffix.lower() in SUFFIXES and not any(p.startswith(".") for p in rel.parts):
            out.append({"name": rel.as_posix(), "chars": len(read(path))})
    return out


def read(path: Path) -> str:
    return path.read_text(encoding="utf-8", errors="replace").strip()


def resolve(folder: Path, name: str) -> Path | None:
    """`name` as a served file inside the folder, or None (outside it, hidden, or not .md / .txt)."""
    if not name or name.startswith(("/", "\\")) or ".." in Path(name).parts:
        return None
    path = (folder / name).resolve()
    try:
        rel = path.relative_to(folder.resolve())
    except ValueError:
        return None
    if any(p.startswith(".") for p in rel.parts) or path.suffix.lower() not in SUFFIXES or not path.is_file():
        return None
    return path


def content(folder: Path, names: list[str], limit: int) -> dict:
    text = ""
    for name in sorted(set(names)):
        path = resolve(folder, name)
        if path is not None:
            text += f"## {name}\n{read(path)}\n\n"
    text = text.strip()
    return {"text": text[:limit], "truncated": len(text) > limit}


def lan_addresses() -> list[str]:
    found = set()
    try:
        with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as s:
            s.connect(("10.255.255.255", 1))  # no packet is sent; picks the LAN interface
            found.add(s.getsockname()[0])
    except OSError:
        pass
    try:
        found.update(a[4][0] for a in socket.getaddrinfo(socket.gethostname(), None, socket.AF_INET))
    except OSError:
        pass
    return sorted(a for a in found if not a.startswith("127."))


def make_handler(folder: Path, token: str, limit: int):
    class Handler(BaseHTTPRequestHandler):
        def do_GET(self) -> None:  # noqa: N802 (http.server naming)
            url = urlparse(self.path)
            query = parse_qs(url.query)
            given = (query.get("token") or [""])[0]
            if not hmac.compare_digest(given.encode(), token.encode()):
                return self.reply(403, {"error": "wrong token"})
            if url.path == "/files":
                return self.reply(200, {"files": list_files(folder)})
            if url.path == "/content":
                names = [n.strip() for n in (query.get("names") or [""])[0].split("\n") if n.strip()]
                return self.reply(200, content(folder, names, limit))
            self.reply(404, {"error": "not found"})

        def reply(self, code: int, body: dict) -> None:
            data = json.dumps(body, ensure_ascii=False).encode("utf-8")
            self.send_response(code)
            self.send_header("Content-Type", "application/json; charset=utf-8")
            self.send_header("Content-Length", str(len(data)))
            self.end_headers()
            self.wfile.write(data)

        def log_message(self, fmt: str, *args) -> None:  # the path carries the token: log the route only
            print(f"{self.address_string()} {self.command} {urlparse(self.path).path} -> {args[1] if len(args) > 1 else ''}")

    return Handler


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--dir", type=Path, default=DEFAULT_DIR, help="the one folder to serve")
    parser.add_argument("--port", type=int, default=8882)
    parser.add_argument("--host", default="0.0.0.0")
    parser.add_argument("--limit", type=int, default=6000, help="characters sent at most per request")
    args = parser.parse_args()
    folder = args.dir.resolve()
    folder.mkdir(parents=True, exist_ok=True)
    token = load_token(folder)
    print(f"Lan Agent knowledge server: {folder}", flush=True)
    print(f"  {len(list_files(folder))} file(s); password: {token}", flush=True)
    for address in lan_addresses() or ["<this computer's IP>"]:
        print(f"  address for the app: http://{address}:{args.port}", flush=True)
    print("  (allow Python on private networks if Windows asks)  Ctrl+C to stop", flush=True)
    ThreadingHTTPServer((args.host, args.port), make_handler(folder, token, args.limit)).serve_forever()


if __name__ == "__main__":
    main()
