"""A stand-in for the customer's cloud, for testing the phone's cloud bridge (docs/cloud-bridge-protocol.md).

Python standard library only. Everything is kept in memory and every event is printed and appended to events.jsonl.

    set MOCK_TOKEN=<a long random string>      (the same one goes into the app: Settings > 云端任务 > 设备密钥)
    py -3 tools/cloud-mock/mock_cloud.py --port 8787

Then, from the same computer:
    py -3 tools/cloud-mock/mock_cloud.py --add "打开天气，告诉我现在的气温"
    py -3 tools/cloud-mock/mock_cloud.py --approve <task_id>      (or --reject <task_id>, --cancel <task_id>)
    py -3 tools/cloud-mock/mock_cloud.py --show <task_id>
"""
import argparse, json, os, sys, threading, time, uuid, urllib.request
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

TOKEN = os.environ.get('MOCK_TOKEN', '')
LOG = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'events.jsonl')
lock = threading.Lock()
tasks = {}        # task_id -> task
queue = []        # task ids not yet given out
devices = {}      # device_id -> last heartbeat


def now():
    return time.strftime('%Y-%m-%dT%H:%M:%SZ', time.gmtime())


def log(kind, data):
    line = {'at': now(), 'kind': kind, **data}
    shown = {k: (v if k != 'screenshot_jpeg_base64' else f'<{len(v)} chars>') for k, v in line.items()}
    print(json.dumps(shown, ensure_ascii=False), flush=True)
    with open(LOG, 'a', encoding='utf-8') as f:
        f.write(json.dumps(line, ensure_ascii=False) + '\n')


class Handler(BaseHTTPRequestHandler):
    def reply(self, code, body):
        data = json.dumps(body, ensure_ascii=False).encode('utf-8')
        self.send_response(code)
        self.send_header('Content-Type', 'application/json; charset=utf-8')
        self.send_header('Content-Length', str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def body(self):
        n = int(self.headers.get('Content-Length') or 0)
        return json.loads(self.rfile.read(n) or b'{}') if n else {}

    def authorized(self):
        if TOKEN and self.headers.get('Authorization') == f'Bearer {TOKEN}':
            return True
        self.reply(401, {'error': 'unauthorized'})
        return False

    def log_message(self, *args):
        pass

    def do_GET(self):
        if not self.authorized():
            return
        parts = self.path.strip('/').split('/')
        if parts[:3] == ['api', 'v1', 'tasks'] and len(parts) == 4:
            with lock:
                task = tasks.get(parts[3])
            return self.reply(200, task) if task else self.reply(404, {'error': 'no such task'})
        if parts[:3] == ['api', 'v1', 'devices']:
            with lock:
                return self.reply(200, {'devices': devices})
        self.reply(404, {'error': 'no such route'})

    def do_POST(self):
        if not self.authorized():
            return
        parts = self.path.strip('/').split('/')
        body = self.body()
        with lock:
            if parts[:3] == ['api', 'v1', 'tasks'] and len(parts) == 3:  # create
                tid = body.get('task_id') or str(uuid.uuid4())
                task = {'task_id': tid, 'type': 'phone_task', 'input': body.get('input', {}),
                        'requires_approval_before_external_action': body.get('requires_approval_before_external_action', True),
                        'target_device': body.get('target_device', 'home_iphone_01'),
                        'idempotency_key': body.get('idempotency_key', tid), 'status': 'queued', 'approval': 'none',
                        'created_at': now(), 'events': []}
                tasks[tid] = task
                queue.append(tid)
                log('created', {'task_id': tid, 'input': task['input']})
                return self.reply(201, task)
            if parts[:3] == ['api', 'v1', 'devices'] and len(parts) == 5 and parts[4] == 'heartbeat':
                device = parts[3]
                devices[device] = {**body, 'seen': now()}
                reply = {'task': None, 'cancel': [t['task_id'] for t in tasks.values()
                                                  if t['status'] == 'cancelled' and t.get('assigned_to') == device]}
                for tid in list(queue):
                    task = tasks[tid]
                    if task['target_device'] in (device, 'any'):
                        queue.remove(tid)
                        task['status'] = 'assigned'
                        task['assigned_to'] = device
                        reply['task'] = {k: task[k] for k in ('task_id', 'type', 'input', 'requires_approval_before_external_action',
                                                             'idempotency_key')}
                        log('assigned', {'task_id': tid, 'device_id': device})
                        break
                return self.reply(200, reply)
            if parts[:3] == ['api', 'v1', 'tasks'] and len(parts) == 5:
                tid, verb = parts[3], parts[4]
                task = tasks.get(tid)
                if not task:
                    return self.reply(404, {'error': 'no such task'})
                if verb == 'events':
                    task['events'].append({k: v for k, v in body.items() if k != 'screenshot_jpeg_base64'})
                    if task['status'] != 'cancelled':
                        task['status'] = body.get('status', task['status'])
                    if 'result' in body:
                        task['result'] = body['result']
                    if body.get('status') == 'retry_pending' and task['status'] != 'cancelled':  # the phone did not take it: queue it again
                        task['status'] = 'queued'
                        task.pop('assigned_to', None)
                        if tid not in queue:
                            queue.append(tid)
                    if body.get('status') == 'waiting_approval':
                        task['approval'] = 'pending'
                        task['approval_request'] = body.get('approval_request')
                    log('event', body)
                    return self.reply(200, {'ok': True})
                if verb in ('approve', 'reject'):
                    task['approval'] = 'approved' if verb == 'approve' else 'rejected'
                    log(verb, {'task_id': tid})
                    return self.reply(200, task)
                if verb == 'cancel':
                    task['status'] = 'cancelled'
                    if tid in queue:
                        queue.remove(tid)
                    log('cancel', {'task_id': tid})
                    return self.reply(200, task)
        self.reply(404, {'error': 'no such route'})


def call(port, method, path, body=None):
    req = urllib.request.Request(f'http://127.0.0.1:{port}{path}', method=method,
                                 data=json.dumps(body).encode('utf-8') if body is not None else None,
                                 headers={'Authorization': f'Bearer {TOKEN}', 'Content-Type': 'application/json'})
    with urllib.request.urlopen(req, timeout=10) as r:
        return json.loads(r.read() or b'{}')


def main():
    sys.stdout.reconfigure(encoding='utf-8')
    p = argparse.ArgumentParser()
    p.add_argument('--port', type=int, default=8787)
    p.add_argument('--add')
    p.add_argument('--no-approval', action='store_true', help='the task may send without asking')
    p.add_argument('--screenshot', action='store_true')
    p.add_argument('--approve')
    p.add_argument('--reject')
    p.add_argument('--cancel')
    p.add_argument('--show')
    a = p.parse_args()
    if not TOKEN:
        sys.exit('set MOCK_TOKEN first (the same value goes into the app)')
    if a.add:
        task = call(a.port, 'POST', '/api/v1/tasks', {'input': {'instruction': a.add, 'want_screenshot': a.screenshot},
                                                      'requires_approval_before_external_action': not a.no_approval})
        print(task['task_id'])
        return
    for verb in ('approve', 'reject', 'cancel'):
        if getattr(a, verb):
            print(json.dumps(call(a.port, 'POST', f'/api/v1/tasks/{getattr(a, verb)}/{verb}'), ensure_ascii=False))
            return
    if a.show:
        print(json.dumps(call(a.port, 'GET', f'/api/v1/tasks/{a.show}'), ensure_ascii=False, indent=1))
        return
    server = ThreadingHTTPServer(('0.0.0.0', a.port), Handler)
    print(f'mock cloud on port {a.port}; events in {LOG}', flush=True)
    server.serve_forever()


if __name__ == '__main__':
    main()
