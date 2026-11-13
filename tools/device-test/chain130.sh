#!/bin/bash
# chain130.sh: after the running wave (cloudq130g.log QDONE), run wave after wave until chain130.stop exists.
# Each wave: wait for the phone to be idle, run cloudq.py <queue> <out>, append QDONE, keep the phone's logs.
cd /e/AgentStorage/esp32/iphone-agent-build13/tools/device-test || exit 1
P="C:/Users/牛杰/AppData/Roaming/uv/tools/pymobiledevice3/Scripts/python.exe"
USB=D:/AIProjects/agent-toolbox/iphone-logs/lan_usb.py
mkdir -p logs_all
# every 8 minutes a copy of debug.log, so nothing is lost when it rolls over at 2 MB
( while [ ! -f chain130.stop ]; do
    "$P" pulllog.py logs_all/tmp >/dev/null 2>&1 && mv logs_all/tmp/debug.log "logs_all/debug-$(date +%m%d-%H%M%S).log"
    sleep 480
  done ) &
PULLER=$!
until grep -q QDONE cloudq130g.log; do sleep 30; done
echo "$(date +%T) wave 1 (r130g) done"
waves="q130b.json:r130b q130c.json:r130c q128g.json:r130g2 q130b.json:r130b2 q130c.json:r130c2 q128g.json:r130g3"
for w in $waves; do
  [ -f chain130.stop ] && break
  q=${w%%:*}; out=${w##*:}
  for i in $(seq 1 40); do
    case "$("$P" $USB status 2>/dev/null | head -c 200)" in *'"running": false'*) break;; esac
    sleep 30
  done
  sleep 15
  echo "$(date +%T) start $q -> $out"
  PYTHONIOENCODING=utf-8 py -3 cloudq.py "$q" "$out" > "cloudq_$out.log" 2>&1
  echo QDONE >> "cloudq_$out.log"
  "$P" pulllog.py "$out/logs_end" >/dev/null 2>&1; "$P" pulllog1.py "$out/logs_end" >/dev/null 2>&1
  echo "$(date +%T) done $out"
done
kill $PULLER 2>/dev/null
echo "$(date +%T) chain over"
