"""ark_cache_probe.py: does Ark prompt caching work for Lan Agent's executor model, with deep thinking off?

Run it yourself:  py -3 ark_cache_probe.py      (it asks for the Ark API key without showing it; the key is not saved)
or with the key in the environment variable ARK_API_KEY. The results (no key in them) go to ark_cache_probe.out.

Sends the executor's real system prompt (prompts/actor.md + app-rules.md, about 10k tokens) a few times:
  A. chat/completions as the app does now (thinking disabled): the baseline.
  B. Context API, common_prefix (official docs: no `thinking` field, needs an endpoint id): does it even start?
  C. Responses API with caching enabled and thinking disabled, chained to one base response with previous_response_id.
For each: HTTP status, seconds, prompt tokens, cached tokens, reasoning tokens. About 8 calls, well under ¥0.1.
"""
import getpass, json, os, sys, time, urllib.error, urllib.request

BASE = 'https://ark.cn-beijing.volces.com/api/v3'
MODEL = sys.argv[1] if len(sys.argv) > 1 else 'doubao-seed-2-1-lite-260915'
HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, '..', '..'))
OUT = os.path.join(HERE, 'ark_cache_probe.out')
SYSTEM = open(os.path.join(ROOT, 'prompts', 'actor.md'), encoding='utf-8').read() + '\n' + \
    open(os.path.join(ROOT, 'prompts', 'app-rules.md'), encoding='utf-8').read()
ASKS = ['Goal: 打开计算器\n\nRecent actions:\n(none)\n\nNext action? Answer with one THINK line and one DO line.',
        'Goal: 打开备忘录\n\nRecent actions:\n(none)\n\nNext action? Answer with one THINK line and one DO line.']
lines = []


def say(s):
    print(s, flush=True)
    lines.append(s)


def post(path, body, key):
    req = urllib.request.Request(BASE + path, data=json.dumps(body).encode('utf-8'), method='POST',
                                 headers={'Authorization': 'Bearer ' + key, 'Content-Type': 'application/json'})
    t0 = time.time()
    try:
        with urllib.request.urlopen(req, timeout=90) as r:
            return r.status, json.loads(r.read() or b'{}'), time.time() - t0
    except urllib.error.HTTPError as e:
        return e.code, {'error': e.read()[:400].decode('utf-8', 'replace')}, time.time() - t0
    except Exception as e:  # noqa: BLE001 - report anything and go on
        return 0, {'error': str(e)[:300]}, time.time() - t0


def usage(d):
    u = d.get('usage') or {}
    p = u.get('prompt_tokens', u.get('input_tokens'))
    c = (u.get('prompt_tokens_details') or u.get('input_tokens_details') or {}).get('cached_tokens')
    r = (u.get('completion_tokens_details') or u.get('output_tokens_details') or {}).get('reasoning_tokens')
    return f'prompt {p} cached {c} reasoning {r}'


def report(name, status, d, secs):
    if status != 200:
        say(f'{name}: HTTP {status} in {secs:.1f}s: {json.dumps(d, ensure_ascii=False)[:300]}')
    else:
        say(f'{name}: OK in {secs:.1f}s, {usage(d)}')


def main():
    key = os.environ.get('ARK_API_KEY') or getpass.getpass('Ark API key (not shown, not saved): ').strip()
    if not key:
        say('no key given'); return
    say(f'model {MODEL}, system prompt {len(SYSTEM)} chars')
    for i, ask in enumerate(ASKS):
        s, d, t = post('/chat/completions', {'model': MODEL, 'max_tokens': 80, 'thinking': {'type': 'disabled'},
                                             'messages': [{'role': 'system', 'content': SYSTEM}, {'role': 'user', 'content': ask}]}, key)
        report(f'A{i + 1} chat, as now', s, d, t)
    s, d, t = post('/context/create', {'model': MODEL, 'mode': 'common_prefix', 'ttl': 3600,
                                       'messages': [{'role': 'system', 'content': SYSTEM}]}, key)
    report('B0 context create', s, d, t)
    ctx = d.get('id') if s == 200 else None
    if ctx:
        for i, ask in enumerate(ASKS):
            s, d, t = post('/context/chat/completions', {'model': MODEL, 'context_id': ctx, 'max_tokens': 80,
                                                         'messages': [{'role': 'user', 'content': ask}]}, key)
            report(f'B{i + 1} context chat', s, d, t)
    # Official docs (docs/ark/context-cache): a prefix cache is made with caching {type: enabled, prefix: true}, no
    # stream, no instructions field; later calls name it in previous_response_id with caching enabled each time, and
    # thinking set as in the first call. It lives 3 days by default (expire_at).
    s, d, t = post('/responses', {'model': MODEL, 'caching': {'type': 'enabled', 'prefix': True}, 'thinking': {'type': 'disabled'},
                                  'expire_at': int(time.time()) + 3600,
                                  'input': [{'role': 'system', 'content': SYSTEM}]}, key)
    report('C0 responses prefix', s, d, t)
    base = d.get('id') if s == 200 else None
    if base:
        for i, ask in enumerate(ASKS):
            s, d, t = post('/responses', {'model': MODEL, 'caching': {'type': 'enabled'}, 'thinking': {'type': 'disabled'},
                                          'previous_response_id': base, 'max_output_tokens': 80,
                                          'input': [{'role': 'user', 'content': ask}]}, key)
            report(f'C{i + 1} responses chained', s, d, t)
            if s == 200 and i == 0:
                text = ''.join(c.get('text', '') for o in d.get('output', []) for c in (o.get('content') or []) if isinstance(c, dict))
                say(f'   reply: {text[:120]!r}')
        # As the app sends a step: a screenshot and the text, and the reply streamed.
        shot = os.path.join(HERE, 'z3trace', '485.jpg')
        if os.path.exists(shot):
            import base64
            url = 'data:image/jpeg;base64,' + base64.b64encode(open(shot, 'rb').read()).decode()
            content = [{'type': 'input_image', 'image_url': url}, {'type': 'input_text', 'text': ASKS[0]}]
            body = {'model': MODEL, 'caching': {'type': 'enabled'}, 'thinking': {'type': 'disabled'}, 'temperature': 0, 'store': False,
                    'previous_response_id': base, 'max_output_tokens': 80, 'input': [{'role': 'user', 'content': content}]}
            s, d, t = post('/responses', body, key)
            report('C3 chained + screenshot', s, d, t)
            body['stream'] = True
            req = urllib.request.Request(BASE + '/responses', data=json.dumps(body).encode('utf-8'), method='POST',
                                         headers={'Authorization': 'Bearer ' + key, 'Content-Type': 'application/json'})
            t0, kinds, text, last = time.time(), [], '', {}
            try:
                with urllib.request.urlopen(req, timeout=90) as r:
                    for raw in r:
                        line = raw.decode('utf-8', 'replace').strip()
                        if not line.startswith('data:'):
                            continue
                        try:
                            ev = json.loads(line[5:].strip())
                        except ValueError:
                            continue
                        k = ev.get('type', '?')
                        if k not in kinds:
                            kinds.append(k)
                        if k == 'response.output_text.delta':
                            text += ev.get('delta', '')
                        if k in ('response.completed', 'response.incomplete', 'response.failed'):
                            last = ev.get('response') or {}
                say(f'C4 chained + screenshot, streamed: {time.time() - t0:.1f}s, {usage(last)}, events {kinds}')
                say(f'   reply: {text[:120]!r}')
            except urllib.error.HTTPError as e:
                say(f'C4 streamed: HTTP {e.code}: {e.read()[:300].decode("utf-8", "replace")}')


if __name__ == '__main__':
    try:
        main()
    finally:
        open(OUT, 'w', encoding='utf-8').write('\n'.join(lines) + '\n')
        print('saved to', OUT)
