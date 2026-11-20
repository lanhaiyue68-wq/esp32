#!/bin/bash
# chain151.sh: user 11-20 ("出 151 只複查三題"): on build 151, only n16, x1, x4 (q151r/). Starts once the phone reports
# app_build 151 (the user installs it); before each item waits while iOS reports serious/critical (at most 15 min), and
# rests 4 min after a short item, 10 min after an x one. Stop: touch chain151.stop.
cd /e/AgentStorage/esp32/iphone-agent-build13/tools/device-test || exit 1
P="C:/Users/牛杰/AppData/Roaming/uv/tools/pymobiledevice3/Scripts/python.exe"
OUT=r151r
mkdir -p logs_151/traces
rm -f chain151.stop chain151.done
dev() { curl -s -H "Authorization: Bearer lan115test" http://127.0.0.1:8787/api/v1/devices; }
until dev | grep -q '"app_build": "151"'; do [ -f chain151.stop ] && exit 0; sleep 60; done
echo "$(date +%T) 151 installed"
usb() { timeout 30 "$P" -m pymobiledevice3 usbmux list 2>/dev/null | grep -q Identifier; }
keep() { usb && PYTHONIOENCODING=utf-8 timeout 150 "$P" trace_keep.py logs_151/traces 2026112 >> logs_151/trace_keep.log 2>&1; }
cool() { for i in $(seq 15); do dev | grep -qE '"thermal": "(serious|critical)"' || return; echo "$(date +%T) hot, waiting"; sleep 60; done; }
( while [ ! -f chain151.stop ] && [ ! -f chain151.done ]; do keep; sleep 300; done ) &
PULLER=$!
for q in q151r/*.json; do
  [ -f chain151.stop ] && break
  cool
  echo "$(date +%T) start $q"
  PYTHONIOENCODING=utf-8 py -3 cloudq.py "$q" "$OUT" >> "cloudq_$OUT.log" 2>&1
  keep
  echo "$(date +%T) done $q"
  case "$q" in *_x*) rest=600 ;; *) rest=240 ;; esac
  [ -f chain151.stop ] && break
  sleep $rest
done
touch chain151.done
kill $PULLER 2>/dev/null
if usb; then
  timeout 120 "$P" pulllog.py "$OUT/logs_end" >/dev/null 2>&1
  timeout 120 "$P" "C:/Users/牛杰/AppData/Local/Temp/claude/3b8568b0d74ff417/9003c9af-ac51-42f7-9282-c0958c35d3e6/scratchpad/pulllog1.py" "$OUT/logs_end" >/dev/null 2>&1
fi
usb && PYTHONIOENCODING=utf-8 timeout 200 "$P" "C:/Users/牛杰/AppData/Local/Temp/claude/2c37ff06cd0c5ed3/e6c13224-2fa7-4a99-a513-2c4ac675562a/scratchpad/trace_keep_all.py" logs_151/traces 2026112 >> logs_151/trace_keep.log 2>&1
echo "$(date +%T) chain over"
