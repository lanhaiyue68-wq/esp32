#!/bin/bash
# chain137.sh: build 136: install-yes check (s0), customer scenarios A-H (s1-s9), then the 135 hell yes/no sets again (r136a, r136b).
# order). No food delivery. Over the cloud; logs pulled only when the phone is on USB.
cd /e/AgentStorage/esp32/iphone-agent-build13/tools/device-test || exit 1
P="C:/Users/牛杰/AppData/Roaming/uv/tools/pymobiledevice3/Scripts/python.exe"
rm -f chain137.stop chain137.done
mkdir -p logs_137
usb() { timeout 30 "$P" -m pymobiledevice3 usbmux list 2>/dev/null | grep -q Identifier; }
( while [ ! -f chain137.stop ] && [ ! -f chain137.done ]; do
    if usb && timeout 120 "$P" pulllog.py logs_137/tmp >/dev/null 2>&1; then
      mv logs_137/tmp/debug.log "logs_137/debug-$(date +%m%d-%H%M%S).log"
    fi
    sleep 360
  done ) &
PULLER=$!
for w in q134h.json:r137h q137s.json:r137s q135a.json:r137a q135b.json:r137b; do
  [ -f chain137.stop ] && break
  q=${w%%:*}; out=${w##*:}
  echo "$(date +%T) start $q -> $out"
  PYTHONIOENCODING=utf-8 py -3 cloudq.py "$q" "$out" > "cloudq_$out.log" 2>&1
  echo QDONE >> "cloudq_$out.log"
  if usb; then
    timeout 120 "$P" pulllog.py "$out/logs_end" >/dev/null 2>&1; timeout 120 "$P" pulllog1.py "$out/logs_end" >/dev/null 2>&1
  fi
  echo "$(date +%T) done $out"
done
touch chain137.done
kill $PULLER 2>/dev/null
echo "$(date +%T) chain over"
