#!/bin/bash
# chain152.sh: user 11-20 ("你把所有的問題都解決了，然后再發一百五十二"): on build 152 (q152r/), the 4 X bloggers that ran
# out of steps on 151 (D195-D201; approve "（关注）" since D196 asks), then x1 (D191) and x4 (D192, D193). Starts once the
# phone reports build 152; waits while iOS reports serious/critical; rests 4 min after a short item, 10 min after x1/x4.
# Stop: touch chain152.stop.
cd /e/AgentStorage/esp32/iphone-agent-build13/tools/device-test || exit 1
P="C:/Users/牛杰/AppData/Roaming/uv/tools/pymobiledevice3/Scripts/python.exe"
OUT=r152r
mkdir -p logs_152/traces
rm -f chain152.stop chain152.done
dev() { curl -s -H "Authorization: Bearer lan115test" http://127.0.0.1:8787/api/v1/devices; }
until dev | grep -q '"app_build": "152"'; do [ -f chain152.stop ] && exit 0; sleep 60; done
echo "$(date +%T) 152 installed"
usb() { timeout 30 "$P" -m pymobiledevice3 usbmux list 2>/dev/null | grep -q Identifier; }
keep() { usb && PYTHONIOENCODING=utf-8 timeout 150 "$P" trace_keep.py logs_152/traces 2026112 >> logs_152/trace_keep.log 2>&1; }
cool() { for i in $(seq 15); do dev | grep -qE '"thermal": "(serious|critical)"' || return; echo "$(date +%T) hot, waiting"; sleep 60; done; }
( while [ ! -f chain152.stop ] && [ ! -f chain152.done ]; do keep; sleep 300; done ) &
PULLER=$!
for q in q152r/*.json; do
  [ -f chain152.stop ] && break
  cool
  echo "$(date +%T) start $q"
  PYTHONIOENCODING=utf-8 py -3 cloudq.py "$q" "$OUT" >> "cloudq_$OUT.log" 2>&1
  keep
  echo "$(date +%T) done $q"
  case "$q" in *_x*) rest=600 ;; *) rest=240 ;; esac
  [ -f chain152.stop ] && break
  sleep $rest
done
touch chain152.done
kill $PULLER 2>/dev/null
if usb; then
  timeout 120 "$P" pulllog.py "$OUT/logs_end" >/dev/null 2>&1
  timeout 120 "$P" "C:/Users/牛杰/AppData/Local/Temp/claude/3b8568b0d74ff417/9003c9af-ac51-42f7-9282-c0958c35d3e6/scratchpad/pulllog1.py" "$OUT/logs_end" >/dev/null 2>&1
fi
usb && PYTHONIOENCODING=utf-8 timeout 200 "$P" "C:/Users/牛杰/AppData/Local/Temp/claude/2c37ff06cd0c5ed3/e6c13224-2fa7-4a99-a513-2c4ac675562a/scratchpad/trace_keep_all.py" logs_152/traces 2026112 >> logs_152/trace_keep.log 2>&1
echo "$(date +%T) chain over"
