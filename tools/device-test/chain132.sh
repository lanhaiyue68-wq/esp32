#!/bin/bash
# chain132.sh: build 132, three waves back to back (q128g, q130b, q130c), stop early when chain132.stop exists.
# Each wave: wait for the phone to be idle, run cloudq.py <queue> <out>, append QDONE, keep the phone's logs.
cd /e/AgentStorage/esp32/iphone-agent-build13/tools/device-test || exit 1
P="C:/Users/牛杰/AppData/Roaming/uv/tools/pymobiledevice3/Scripts/python.exe"
USB=D:/AIProjects/agent-toolbox/iphone-logs/lan_usb.py
rm -f chain132.stop
mkdir -p logs_132
# every 6 minutes a copy of debug.log, so nothing is lost when it rolls over at 2 MB
( while [ ! -f chain132.stop ] && [ ! -f chain132.done ]; do
    "$P" pulllog.py logs_132/tmp >/dev/null 2>&1 && mv logs_132/tmp/debug.log "logs_132/debug-$(date +%m%d-%H%M%S).log"
    sleep 360
  done ) &
PULLER=$!
for w in q128g.json:r132g q130b.json:r132b q130c.json:r132c; do
  [ -f chain132.stop ] && break
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
touch chain132.done
kill $PULLER 2>/dev/null
echo "$(date +%T) chain over"
