#!/bin/bash
# phone reports build 156; waits while iOS reports serious/critical; rests 4 min after a short item, 10 min after x1/x4.
# Stop: touch chain156.stop.
cd /e/AgentStorage/esp32/iphone-agent-build13/tools/device-test || exit 1
P="C:/Users/牛杰/AppData/Roaming/uv/tools/pymobiledevice3/Scripts/python.exe"
OUT=r156r
mkdir -p logs_156/traces
rm -f chain156.stop chain156.done
dev() { curl -s -H "Authorization: Bearer lan115test" http://127.0.0.1:8787/api/v1/devices; }
until dev | grep -q '"app_build": "156"'; do [ -f chain156.stop ] && exit 0; sleep 60; done
echo "$(date +%T) 156 ready"
usb() { timeout 30 "$P" -m pymobiledevice3 usbmux list 2>/dev/null | grep -q Identifier; }
keep() { usb && PYTHONIOENCODING=utf-8 timeout 150 "$P" trace_keep.py logs_156/traces 2026112 >> logs_156/trace_keep.log 2>&1; }
cool() { for i in $(seq 15); do dev | grep -qE '"thermal": "(serious|critical)"' || return; echo "$(date +%T) hot, waiting"; sleep 60; done; }
( while [ ! -f chain156.stop ] && [ ! -f chain156.done ]; do keep; sleep 300; done ) &
PULLER=$!
for q in q156r/*.json; do
  [ -f chain156.stop ] && break
  cool
  echo "$(date +%T) start $q"
  PYTHONIOENCODING=utf-8 py -3 cloudq.py "$q" "$OUT" >> "cloudq_$OUT.log" 2>&1
  keep
  echo "$(date +%T) done $q"
  case "$q" in *_x*) rest=600 ;; *) rest=150 ;; esac
  [ -f chain156.stop ] && break
  sleep $rest
done
touch chain156.done
kill $PULLER 2>/dev/null
if usb; then
  timeout 120 "$P" pulllog.py "$OUT/logs_end" >/dev/null 2>&1
  timeout 120 "$P" "C:/Users/牛杰/AppData/Local/Temp/claude/3b8568b0d74ff417/9003c9af-ac51-42f7-9282-c0958c35d3e6/scratchpad/pulllog1.py" "$OUT/logs_end" >/dev/null 2>&1
fi
usb && PYTHONIOENCODING=utf-8 timeout 200 "$P" "C:/Users/牛杰/AppData/Local/Temp/claude/2c37ff06cd0c5ed3/e6c13224-2fa7-4a99-a513-2c4ac675562a/scratchpad/trace_keep_all.py" logs_156/traces 2026112 >> logs_156/trace_keep.log 2>&1
echo "$(date +%T) chain over"
