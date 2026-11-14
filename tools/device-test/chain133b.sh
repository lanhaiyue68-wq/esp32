#!/bin/bash
# chain133b.sh: after chain133 (round 1), round 2 = q133h (one everyday request at a time), round 3 = the three
# waves again (r133g2/b2/c2). Stops early when chain133b.stop exists. Logs into logs_133 as in chain133.sh.
cd /e/AgentStorage/esp32/iphone-agent-build13/tools/device-test || exit 1
P="C:/Users/牛杰/AppData/Roaming/uv/tools/pymobiledevice3/Scripts/python.exe"
USB=D:/AIProjects/agent-toolbox/iphone-logs/lan_usb.py
rm -f chain133b.stop chain133b.done
until [ -f chain133.done ] || [ -f chain133b.stop ]; do sleep 30; done
mkdir -p logs_133
( while [ ! -f chain133b.stop ] && [ ! -f chain133b.done ]; do
    "$P" pulllog.py logs_133/tmp >/dev/null 2>&1 && mv logs_133/tmp/debug.log "logs_133/debug-$(date +%m%d-%H%M%S).log"
    sleep 360
  done ) &
PULLER=$!
for w in q133h.json:r133h q128g.json:r133g2 q130b.json:r133b2 q130c.json:r133c2; do
  [ -f chain133b.stop ] && break
  q=${w%%:*}; out=${w##*:}
  for i in $(seq 1 40); do
    case "$("$P" $USB status 2>/dev/null | head -c 200)" in *'"running": false'*) break;; esac
    sleep 30
  done
  sleep 10
  echo "$(date +%T) start $q -> $out"
  PYTHONIOENCODING=utf-8 py -3 cloudq.py "$q" "$out" > "cloudq_$out.log" 2>&1
  echo QDONE >> "cloudq_$out.log"
  "$P" pulllog.py "$out/logs_end" >/dev/null 2>&1; "$P" pulllog1.py "$out/logs_end" >/dev/null 2>&1
  echo "$(date +%T) done $out"
done
touch chain133b.done
kill $PULLER 2>/dev/null
echo "$(date +%T) chain over"
