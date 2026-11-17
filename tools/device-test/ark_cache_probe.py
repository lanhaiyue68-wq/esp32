"""ark_cache_probe.py: does Ark prompt caching work for Lan Agent's executor model, with deep thinking off?

Run it yourself:  py -3 ark_cache_probe.py      (it asks for the Ark API key without showing it; the key is not saved)
or with the key in the environment variable ARK_API_KEY. The results (no key in them) go to ark_cache_probe.out.

Second round (11-17). The first two runs showed: chat/completions as the app sends it got 9016 of 9242 tokens from a
cache on the second run (0 on the first), and a chained Responses call refuses `store: false` with caching. So this
round asks, each time with a system prompt never sent before (a random tag in front, so no old cache can answer):
  N1/N2  chat/completions exactly as the app sends a step (screenshot, temperature 0, thinking off, streamed), twice:
         does the second call come from a cache on its own?
  P0/P1  a Responses prefix cache made for another new prompt, then chat/completions as the app sends it on that
         prompt: does the app's own request read a cache the Responses API made?
  P2     a chained Responses step as D101 sends it, but kept (store left as is) for only 10 minutes: does it work?
About 5 calls of ~10k tokens, well under ¥0.1.
"""
import base64, getpass, json, os, random, sys, time, urllib.error, urllib.request

BASE = 'https://ark.cn-beijing.volces.com/api/v3'
MODEL = sys.argv[1] if len(sys.argv) > 1 else 'doubao-seed-2-1-lite-260915'
HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, '..', '..'))
OUT = os.path.join(HERE, 'ark_cache_probe.out')
SYSTEM = open(os.path.join(ROOT, 'prompts', 'actor.md'), encoding='utf-8').read() + '\n' + \
    open(os.path.join(ROOT, 'prompts', 'app-rules.md'), encoding='utf-8').read()
ASK = 'Goal: 打开计算器\n\nRecent actions:\n(none)\n\nNext action? Answer with one THINK line and one DO line.'
SHOT = 'data:image/jpeg;base64,' + base64.b64encode(open(os.path.join(HERE, 'z3trace', '485.jpg'), 'rb').read()).decode()
lines = []


def say(s):
    print(s, flush=True)
    lines.append(s)


def usage(u):
    u = u or {}
    p = u.get('prompt_tokens', u.get('input_tokens'))
    c = (u.get('prompt_tokens_details') or u.get('input_tokens_details') or {}).get('cached_tokens')
    r = (u.get('completion_tokens_details') or u.get('output_tokens_details') or {}).get('reasoning_tokens')
    return f'prompt {p} cached {c} reasoning {r}'


def call(path, body, key, stream):
    """(status, seconds, usage, reply text, event kinds or error)."""
    req = urllib.request.Request(BASE + path, data=json.dumps(body).encode('utf-8'), method='POST',
                                 headers={'Authorization': 'Bearer ' + key, 'Content-Type': 'application/json'})
    t0 = time.time()
    try:
        with urllib.request.urlopen(req, timeout=90) as r:
            if not stream:
                d = json.loads(r.read() or b'{}')
                return 200, time.time() - t0, d.get('usage'), d.get('id', ''), ''
            u, text, kinds = None, '', []
            for raw in r:
                line = raw.decode('utf-8', 'replace').strip()
                if not line.startswith('data:') or line[5:].strip() == '[DONE]':
                    continue
                try:
                    ev = json.loads(line[5:].strip())
                except ValueError:
                    continue
                k = ev.get('type', 'chunk')
                if k not in kinds:
                    kinds.append(k)
                if ev.get('usage'):
                    u = ev['usage']
                for ch in ev.get('choices') or []:
                    text += (ch.get('delta') or {}).get('content') or ''
                if k == 'response.output_text.delta':
                    text += ev.get('delta', '')
                if k in ('response.completed', 'response.incomplete', 'response.failed'):
                    u = (ev.get('response') or {}).get('usage') or u
            return 200, time.time() - t0, u, text, kinds
    except urllib.error.HTTPError as e:
        return e.code, time.time() - t0, None, '', e.read()[:300].decode('utf-8', 'replace')
    except Exception as e:  # noqa: BLE001 - report anything and go on
        return 0, time.time() - t0, None, '', str(e)[:300]


def report(name, res, show_reply=False):
    status, secs, u, text, extra = res
    if status != 200:
        say(f'{name}: HTTP {status} in {secs:.1f}s: {extra}')
        return
    say(f'{name}: OK in {secs:.1f}s, {usage(u) if u else "no usage sent"}' + (f', events {extra}' if extra else ''))
    if show_reply:
        say(f'   reply: {text[:120]!r}')


def app_step(system, key):
    """A step as the app sends it now (LLMClient.once): chat/completions, screenshot first, streamed."""
    return call('/chat/completions', {
        'model': MODEL, 'temperature': 0, 'thinking': {'type': 'disabled'}, 'max_tokens': 80, 'stream': True,
        'messages': [{'role': 'system', 'content': system},
                     {'role': 'user', 'content': [{'type': 'image_url', 'image_url': {'url': SHOT}},
                                                  {'type': 'text', 'text': ASK}]}]}, key, True)


def main():
    key = os.environ.get('ARK_API_KEY') or getpass.getpass('Ark API key (not shown, not saved): ').strip()
    if not key:
        say('no key given'); return
    tag1, tag2 = (f'[run {random.randrange(10**9)}]\n' for _ in range(2))
    say(f'model {MODEL}, system prompt {len(SYSTEM)} chars, each run with a new tag in front')
    report('N1 app step, new prompt', app_step(tag1 + SYSTEM, key), show_reply=True)
    report('N2 app step, same prompt again', app_step(tag1 + SYSTEM, key))
    res = call('/responses', {'model': MODEL, 'caching': {'type': 'enabled', 'prefix': True}, 'thinking': {'type': 'disabled'},
                              'expire_at': int(time.time()) + 3600,
                              'input': [{'role': 'system', 'content': tag2 + SYSTEM}]}, key, False)
    report('P0 responses prefix, another new prompt', res)
    base = res[3] if res[0] == 200 else None
    report('P1 app step on that prompt', app_step(tag2 + SYSTEM, key))
    if base:
        report('P2 responses chained, kept 10 min, screenshot, streamed', call('/responses', {
            'model': MODEL, 'caching': {'type': 'enabled'}, 'thinking': {'type': 'disabled'}, 'temperature': 0,
            'previous_response_id': base, 'expire_at': int(time.time()) + 600, 'max_output_tokens': 80, 'stream': True,
            'input': [{'role': 'user', 'content': [{'type': 'input_image', 'image_url': SHOT},
                                                   {'type': 'input_text', 'text': ASK}]}]}, key, True), show_reply=True)


if __name__ == '__main__':
    try:
        main()
    finally:
        open(OUT, 'w', encoding='utf-8').write('\n'.join(lines) + '\n')
        print('saved to', OUT)
