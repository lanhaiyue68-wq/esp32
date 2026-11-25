"""Send one 智微兔/智企微行 order to Echo through the local mock and print the result compactly.
usage: py -3.12 order.py <geren|qiwei> '<item json>' [wait seconds]"""
import json, sys, urllib.request, time
port = {"geren": 18971, "qiwei": 18970}[sys.argv[1]]
item = json.loads(sys.argv[2]); wait = int(sys.argv[3]) if len(sys.argv) > 3 else 180
t = time.time()
req = urllib.request.Request(f"http://127.0.0.1:{port}/send?wait={wait}", data=json.dumps(item, ensure_ascii=False).encode(),
                             headers={"Content-Type": "application/json; charset=utf-8"}, method="POST")
try:
    r = json.loads(urllib.request.urlopen(req, timeout=wait + 30).read().decode())
except Exception as e:
    r = {"ok": False, "error": str(e)}
res = r.get("result") or {}
first = (res.get("list") or [None])[0] if isinstance(res, dict) else None
def short(v, n=300):
    s = json.dumps(v, ensure_ascii=False); return s if len(s) <= n else s[:n] + "…"
print(f"[{sys.argv[1]} {item.get('type')}] {round(time.time()-t)}s ok={r.get('ok')} result={short(first)}")
