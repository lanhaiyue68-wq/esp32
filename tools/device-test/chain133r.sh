#!/bin/bash
# chain133r.sh: the rest of the 133 plan after USB dropped at 16:01 (pulllog1 hung): r133c, then q133h (everyday
# requests one at a time), then the three waves again. cloudq.py waits for the phone over the cloud (Wi-Fi), so
# nothing here needs USB; logs are pulled only when the phone is on USB, each pull at most 120 s.
cd /e/AgentStorage/esp32/iphone-agent-build13/tools/device-test || exit 1
P="C:/Users/牛杰/AppData/Roaming/uv/tools/pymobiledevice3/Scripts/python.exe"
rm -f chain133r.stop chain133r.done
mkdir -p logs_133
usb() { timeout 30 "$P" -m pymobiledevice3 usbmux list 2>/dev/null | grep -q Identifier; }
( while [ ! -f chain133r.stop ] && [ ! -f chain133r.done ]; do
    if usb && timeout 120 "$P" pulllog.py logs_133/tmp >/dev/null 2>&1; then
      mv logs_133/tmp/debug.log "logs_133/debug-$(date +%m%d-%H%M%S).log"
    fi
    sleep 360
  done ) &
PULLER=$!
for w in q130c.json:r133c q133h.json:r133h q128g.json:r133g2 q130b.json:r133b2 q130c.json:r133c2; do
  [ -f chain133r.stop ] && break
  q=${w%%:*}; out=${w##*:}
  echo "$(date +%T) start $q -> $out"
  PYTHONIOENCODING=utf-8 py -3 cloudq.py "$q" "$out" > "cloudq_$out.log" 2>&1
  echo QDONE >> "cloudq_$out.log"
  if usb; then
    timeout 120 "$P" pulllog.py "$out/logs_end" >/dev/null 2>&1; timeout 120 "$P" pulllog1.py "$out/logs_end" >/dev/null 2>&1
  fi
  echo "$(date +%T) done $out"
done
touch chain133r.done
kill $PULLER 2>/dev/null
echo "$(date +%T) chain over"
