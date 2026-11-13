"""group_report.py <out dir> <group id> <cloudq log>: one group's answer, timing and the log lines worth reading.
Merges every debug log copy (logs_all, the out dir) with a fresh pull, then cuts the group's window (UTC)."""
import glob, json, os, re, subprocess, sys, datetime
os.chdir(r'E:/AgentStorage/esp32/iphone-agent-build13/tools/device-test')
out, gid, qlog = sys.argv[1], sys.argv[2], sys.argv[3]
P = r'C:/Users/牛杰/AppData/Roaming/uv/tools/pymobiledevice3/Scripts/python.exe'
fresh = os.path.join(out, 'logs_fresh')
subprocess.run([P, 'pulllog.py', fresh], capture_output=True)
subprocess.run([P, 'pulllog1.py', fresh], capture_output=True)
lines = set()
for f in glob.glob('logs_all/*.log') + glob.glob('logs_13[1-9]/*.log') + glob.glob(os.path.join(out, '*', 'debug*.log')):
    with open(f, encoding='utf-8', errors='replace') as h:
        lines.update(h.read().splitlines())
L = sorted(l for l in lines if l[:4] == '2026')
# the group's window: its start in the cloudq log (KST) to the next start or now
starts = [(m[1], m[2]) for m in (re.match(r'(\d\d:\d\d:\d\d) (\S+) ', l) for l in open(qlog, encoding='utf-8')) if m]
# The cloudq log has times only: its day is the day the file was made (KST), and each start earlier than the one
# before it is the next day (a wave that runs past midnight).
day = datetime.date.fromtimestamp(os.path.getctime(qlog))
dated, last = [], ''
for hms, g in starts:
    if last and hms < last: day += datetime.timedelta(days=1)
    dated.append((f'{day.isoformat()}T{hms}', g)); last = hms
def utc(stamp): return (datetime.datetime.fromisoformat(stamp) - datetime.timedelta(hours=9)).strftime('%Y-%m-%dT%H:%M:%S')
i = [s[1] for s in dated].index(gid)
a = utc(dated[i][0]); b = utc(dated[i + 1][0]) if i + 1 < len(dated) else '9999'
W = [l for l in L if a <= l[:19] < b]
win = os.path.join(out, f'{gid}.log')
open(win, 'w', encoding='utf-8').write('\n'.join(W) + '\n')
d = [json.loads(l) for l in open(os.path.join(out, 'results.jsonl'), encoding='utf-8') if json.loads(l)['id'] == gid][-1]
print(gid, d['status'], d['seconds'], 's', d['steps'], 'steps;', len(W), 'log lines', a, b)
print('ANSWER:', d['answer'])
print(subprocess.run(['py', '-3', '-X', 'utf8', '-I', 'timing.py', win, a, b], capture_output=True, text=True).stdout)
keys = r'stale plan: the words|is what the goal says to write|is on screen, not the app|learned send|send: the learned|forgotten|a part of|done check:|done: an item|still on the Home Screen after|refused reason|loop reason|reading the Home Screen|page\(s\) read|lift now|未能完成|part stalled|finished:|approval|blocked reason|fail reason'
for l in W:
    if re.search(keys, l): print(l[14:23], l[24:200])
