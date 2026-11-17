"""cloudq.py <queue.json> <out dir> [first id]: run a queue through the mock cloud over Wi-Fi, one task at a time.
Waits for the phone to be idle; a busy reply is tried again; a message is approved only when its text is in the instruction.
Each result and its last screen are kept in <out dir>."""
import ast, base64, json, os, re, sys, time, urllib.request


def fits_text(text, item):
    """A message the instruction asks for: its quoted words exactly, or an approve_if entry exactly; the entry with a
    time after it only where the instruction says to add the time (142's z6: "Z6全部做完12:42" was approved because it
    contained "Z6全部做完", and went out unasked)."""
    t = (text or '').strip()
    if not t:
        return False
    words = item.get('approve_if', [])
    if isinstance(words, str):
        words = ast.literal_eval(words)  # some queue files keep the list as its repr
    if t in words or ('“' + t + '”') in item['task'] or ('"' + t + '"') in item['task']:
        return True
    for w in words:
        if re.fullmatch(re.escape(w) + r'\s*\d{1,2}[:：]\d{2}', t) and                 re.search('“' + re.escape(w) + '”[^；]{0,40}(时间|時間)', item['task']):
            return True
    return False
sys.stdout.reconfigure(encoding='utf-8')
BASE, TOKEN = 'http://127.0.0.1:8787', 'lan115test'
queue, out = json.load(open(sys.argv[1], encoding='utf-8')), sys.argv[2]
start_at = sys.argv[3] if len(sys.argv) > 3 else None
os.makedirs(out, exist_ok=True)


def call(method, path, body=None):
    req = urllib.request.Request(BASE + path, method=method, data=json.dumps(body).encode() if body is not None else None,
                                 headers={'Authorization': f'Bearer {TOKEN}', 'Content-Type': 'application/json'})
    with urllib.request.urlopen(req, timeout=15) as r:
        return json.loads(r.read() or b'{}')


def phone():
    d = call('GET', '/api/v1/devices').get('devices', {}).get('home_iphone_01', {})
    seen = d.get('seen', '')
    age = time.time() - time.mktime(time.strptime(seen, '%Y-%m-%dT%H:%M:%SZ')) + time.timezone * 0 if seen else 1e9
    return d, age


def wait_idle(limit=900):
    t0 = time.time()
    while time.time() - t0 < limit:
        d, _ = phone()
        caps = d.get('capabilities', {})
        hot = False  # user 11-12: run straight on, the phone is not hot (it reads serious while charging under a cooler)
        if hot and int(time.time() - t0) % 60 < 5:
            print(time.strftime('%H:%M:%S'), '   phone is', caps.get('thermal'), '- waiting for it to cool', flush=True)
        if caps.get('agent') == 'idle' and not d.get('running_task_id') and not hot:
            return caps
        time.sleep(5)
    return None


done = {json.loads(l)['id'] for l in open(os.path.join(out, 'results.jsonl'), encoding='utf-8')} if os.path.exists(os.path.join(out, 'results.jsonl')) else set()
started = start_at is None
for item in queue:
    started = started or item['id'] == start_at
    if not started or item['id'] in done:
        continue
    caps = wait_idle()
    if caps is None:
        print('phone not idle for 15 min; stopping', flush=True)
        break
    bad = [k for k in ('screen_capture', 'hid_board', 'pointer') if caps.get(k) != 'available']
    if bad:
        print(time.strftime('%H:%M:%S'), 'phone cannot work now:', caps, flush=True)
        time.sleep(30)
    t0 = time.time()
    print(time.strftime('%H:%M:%S'), item['id'], item['task'], flush=True)
    for attempt in range(3):
        tid = call('POST', '/api/v1/tasks', {'input': {'instruction': item['task'], 'want_screenshot': True},
                                             'requires_approval_before_external_action': True})['task_id']
        answered = set()
        while time.time() - t0 < item.get('limit', 600) + 120:
            task = call('GET', f'/api/v1/tasks/{tid}')
            pend_text = (task.get('approval_request') or {}).get('text', '')
            if task.get('approval') == 'pending' and (pend_text, task.get('approval_seq')) not in answered:
                text = pend_text
                fits = fits_text(text, item)
                dest = (task.get('approval_request') or {}).get('destination') or ''
                fits = fits and (not dest or any(g in dest for g in ('测试群', '验证群', '測試群', '驗證群')))  # only the two test groups
                verdict = 'approve' if fits and not item.get('reject') else 'reject'
                # build 135: "install_app" asks whether to download a missing app; per item "install": "approve" or
                # "reject" (the default: the task ends, as the owner asked on 11-15)
                if (task.get('approval_request') or {}).get('action') == 'install_app':
                    verdict = item.get('install', 'reject')
                # build 136 (D28): "publish_post" asks before 发布; tests stop before publishing (user 11-15), so the default
                # is "reject" unless an item says "publish": "approve"
                if (task.get('approval_request') or {}).get('action') == 'publish_post':
                    verdict = item.get('publish', 'reject')
                # build 138 (D59): "human_verify" asks the owner to do a security check by hand; nobody does it in an
                # unattended run, so the default is "reject" (the thing is left not done) unless an item says "verify": "approve"
                if (task.get('approval_request') or {}).get('action') == 'human_verify':
                    verdict = item.get('verify', 'reject')
                call('POST', f'/api/v1/tasks/{tid}/{verdict}')
                answered.add((text, task.get('approval_seq')))
                time.sleep(2)
                print('   approval asked for', repr(text), 'at', repr((task.get('approval_request') or {}).get('destination')), '->', verdict, flush=True)
            if task['status'] in ('succeeded', 'failed', 'cancelled', 'retry_pending'):
                break
            time.sleep(3)
        if task['status'] != 'retry_pending':
            break
        print('   phone busy; again', flush=True)
        wait_idle()
    if task['status'] not in ('succeeded', 'failed', 'cancelled'):
        print('   timed out while', task['status'], '; cancelling', flush=True)
        call('POST', f'/api/v1/tasks/{tid}/cancel')
        time.sleep(5)
        task = call('GET', f'/api/v1/tasks/{tid}')
    secs = round(time.time() - t0)
    result = task.get('result') or {}
    print('   ->', task['status'], secs, 's', str(result.get('answer', ''))[:160], flush=True)
    shot = None
    for line in open(r'E:\AgentStorage\esp32\iphone-agent-build13\tools\cloud-mock\events.jsonl', encoding='utf-8'):
        e = json.loads(line)
        if e.get('task_id') == tid and e.get('screenshot_jpeg_base64'):
            shot = e['screenshot_jpeg_base64']
    if shot:
        open(os.path.join(out, item['id'] + '.jpg'), 'wb').write(base64.b64decode(shot))
    with open(os.path.join(out, 'results.jsonl'), 'a', encoding='utf-8') as f:
        f.write(json.dumps({'id': item['id'], 'task': item['task'], 'status': task['status'], 'seconds': secs,
                            'answer': result.get('answer', ''), 'steps': result.get('steps'), 'events': [e['status'] for e in task['events']],
                            'error': next((e.get('error_code') for e in task['events'] if e.get('error_code')), None)}, ensure_ascii=False) + '\n')
print('CLOUD QUEUE DONE', flush=True)
