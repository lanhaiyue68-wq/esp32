#!/bin/bash
# chain148b.sh: user 11-19 19:35 ("我現在要出門一趟…你測完了還繼續測，等我回來"): after chain148 is over, the s, h2 and x
# sets once more on the same build 148, to tell steady failures from chance ones. Same keeping of traces and logs.
cd /e/AgentStorage/esp32/iphone-agent-build13/tools/device-test || exit 1
P="C:/Users/牛杰/AppData/Roaming/uv/tools/pymobiledevice3/Scripts/python.exe"
until grep -q "chain over" chain148.out 2>/dev/null; do sleep 60; done
rm -f chain148b.stop chain148b.done
usb() { timeout 30 "$P" -m pymobiledevice3 usbmux list 2>/dev/null | grep -q Identifier; }
keep() { usb && PYTHONIOENCODING=utf-8 timeout 150 "$P" trace_keep.py logs_148/traces 202611 >> logs_148/trace_keep.log 2>&1; }
( while [ ! -f chain148b.stop ] && [ ! -f chain148b.done ]; do
    keep
    sleep 300
  done ) &
PULLER=$!
for w in q148s.json:r148s2 q148h2.json:r148h2b q133x.json:r148x2; do
  [ -f chain148b.stop ] && break
  q=${w%%:*}; out=${w##*:}
  echo "$(date +%T) start $q -> $out"
  PYTHONIOENCODING=utf-8 py -3 cloudq.py "$q" "$out" > "cloudq_$out.log" 2>&1
  echo QDONE >> "cloudq_$out.log"
  if usb; then
    timeout 120 "$P" pulllog.py "$out/logs_end" >/dev/null 2>&1; timeout 120 "$P" "C:/Users/牛杰/AppData/Local/Temp/claude/3b8568b0d74ff417/9003c9af-ac51-42f7-9282-c0958c35d3e6/scratchpad/pulllog1.py" "$out/logs_end" >/dev/null 2>&1
  fi
  keep
  echo "$(date +%T) done $out"
done
touch chain148b.done
kill $PULLER 2>/dev/null
sleep 60; keep; usb && timeout 150 "$P" "C:/Users/牛杰/AppData/Local/Temp/claude/3b8568b0d74ff417/9003c9af-ac51-42f7-9282-c0958c35d3e6/scratchpad/trace_last.py" logs_148/traces >> logs_148/trace_keep.log 2>&1
echo "$(date +%T) chain over"
