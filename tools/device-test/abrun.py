"""abrun.py <queue.json>: each task twice, with the tap tolerance switched off and on over the USB test channel (half the
tasks off first, half on first, so learned routes favour neither). Results go to cloud1222_off / cloud1222_on; the UTC
window of every run is kept in abruns.jsonl so the phone's log can be split by run."""
import json, os, subprocess, sys, time

HERE = os.path.dirname(os.path.abspath(__file__))
PY_USB = r"C:/Users/牛杰/AppData/Roaming/uv/tools/pymobiledevice3/Scripts/python.exe"
LAN = r"D:/AIProjects/agent-toolbox/iphone-logs/lan_usb.py"
env = dict(os.environ, PYTHONIOENCODING='utf-8')
queue = json.load(open(sys.argv[1], encoding='utf-8'))


def switch(on):
    code = ("import asyncio,sys; sys.path.insert(0, r'D:/AIProjects/agent-toolbox/iphone-logs'); from lan_usb import call; "
            f"print(asyncio.run(call('POST', '/tapfast', {{'on': {str(on)}}})))")
    out = subprocess.run([PY_USB, '-c', code], capture_output=True, text=True, env=env, timeout=60)
    return (out.stdout or out.stderr).strip()[-120:]


for i, item in enumerate(queue):
    modes = ['off', 'on'] if i < len(queue) // 2 else ['on', 'off']
    for mode in modes:
        print(time.strftime('%H:%M:%S'), item['id'], mode, 'switch:', switch(mode == 'on'), flush=True)
        one = os.path.join(HERE, f'ab_{item["id"]}_{mode}.json')
        json.dump([dict(item, id=f'{item["id"]}_{mode}')], open(one, 'w', encoding='utf-8'), ensure_ascii=False)
        start = time.strftime('%Y-%m-%dT%H:%M:%S', time.gmtime())
        subprocess.run([sys.executable, os.path.join(HERE, 'cloudq.py'), one, os.path.join(HERE, f'cloud1222_{mode}')],
                       env=env, cwd=HERE)
        end = time.strftime('%Y-%m-%dT%H:%M:%S', time.gmtime())
        with open(os.path.join(HERE, 'abruns.jsonl'), 'a', encoding='utf-8') as f:
            f.write(json.dumps({'id': item['id'], 'mode': mode, 'start': start, 'end': end}) + '\n')
print('AB DONE', flush=True)
