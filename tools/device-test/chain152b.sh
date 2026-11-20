#!/bin/bash
# chain152b.sh: user 11-20 ("現在去X上博主爬取帖子然後吸收乾貨", "關注這些"): on X, one item per followed blogger
# (q152b/), the latest 5 posts each, read only. Run after X is installed and the owner signed in by hand (the agent never
# signs in). Before each item waits while iOS reports serious/critical (at most 15 min); rests 2 min after each.
# Stop: touch chain152b.stop.
cd /e/AgentStorage/esp32/iphone-agent-build13/tools/device-test || exit 1
P="C:/Users/牛杰/AppData/Roaming/uv/tools/pymobiledevice3/Scripts/python.exe"
OUT=r152b
mkdir -p logs_152/traces
rm -f chain152b.stop chain152b.done
dev() { curl -s -H "Authorization: Bearer lan115test" http://127.0.0.1:8787/api/v1/devices; }
usb() { timeout 30 "$P" -m pymobiledevice3 usbmux list 2>/dev/null | grep -q Identifier; }
keep() { usb && PYTHONIOENCODING=utf-8 timeout 150 "$P" trace_keep.py logs_152/traces 2026112 >> logs_152/trace_keep.log 2>&1; }
cool() { for i in $(seq 15); do dev | grep -qE '"thermal": "(serious|critical)"' || return; echo "$(date +%T) hot, waiting"; sleep 60; done; }
# Starts once x_login.ok exists (touched when the owner says X is signed in) and the X install item is over.
until [ -f x_login.ok ] && ! pgrep -f "cloudq.py q152x" >/dev/null 2>&1; do [ -f chain152b.stop ] && exit 0; sleep 30; done
echo "$(date +%T) X signed in; start"
( while [ ! -f chain152b.stop ] && [ ! -f chain152b.done ]; do keep; sleep 300; done ) &
PULLER=$!
for q in q152b/*.json; do
  [ -f chain152b.stop ] && break
  cool
  echo "$(date +%T) start $q"
  PYTHONIOENCODING=utf-8 py -3 cloudq.py "$q" "$OUT" >> "cloudq_$OUT.log" 2>&1
  echo "$(date +%T) done $q"
  [ -f chain152b.stop ] && break
  sleep 120
done
touch chain152b.done
kill $PULLER 2>/dev/null
if usb; then
  timeout 120 "$P" pulllog.py "$OUT/logs_end" >/dev/null 2>&1
  timeout 120 "$P" "C:/Users/牛杰/AppData/Local/Temp/claude/3b8568b0d74ff417/9003c9af-ac51-42f7-9282-c0958c35d3e6/scratchpad/pulllog1.py" "$OUT/logs_end" >/dev/null 2>&1
fi
usb && PYTHONIOENCODING=utf-8 timeout 200 "$P" "C:/Users/牛杰/AppData/Local/Temp/claude/2c37ff06cd0c5ed3/e6c13224-2fa7-4a99-a513-2c4ac675562a/scratchpad/trace_keep_all.py" logs_152/traces 2026112 >> logs_152/trace_keep.log 2>&1
echo "$(date +%T) chain over"
