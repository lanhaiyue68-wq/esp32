#!/bin/bash
# chain131.sh: build 131, three waves back to back (q128g, q130b, q130c), stop early when chain131.stop exists.
# Each wave: wait for the phone to be idle, run cloudq.py <queue> <out>, append QDONE, keep the phone's logs.
cd /e/AgentStorage/esp32/iphone-agent-build13/tools/device-test || exit 1
P="C:/Users/牛杰/AppData/Roaming/uv/tools/pymobiledevice3/Scripts/python.exe"
USB=D:/AIProjects/agent-toolbox/iphone-logs/lan_usb.py
rm -f chain131.stop
mkdir -p logs_131
# every 6 minutes a copy of debug.log, so nothing is lost when it rolls over at 2 MB
( while [ ! -f chain131.stop ] && [ ! -f chain131.done ]; do
    "$P" pulllog.py logs_131/tmp >/dev/null 2>&1 && mv logs_131/tmp/debug.log "logs_131/debug-$(date +%m%d-%H%M%S).log"
    sleep 360
  done ) &
PULLER=$!
for w in q128g.json:r131g q130b.json:r131b q130c.json:r131c; do
  [ -f chain131.stop ] && break
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
touch chain131.done
kill $PULLER 2>/dev/null
echo "$(date +%T) chain over"
