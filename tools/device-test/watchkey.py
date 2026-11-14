import sys, json
try:
    d = json.load(sys.stdin)
    print(d.get('running'), d.get('steps'), len(d.get('task', '')), d.get('task', '')[:60])
except Exception:
    print('no-usb')
