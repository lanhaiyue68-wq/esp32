#!/bin/bash
# chain133x.sh: after chain133r (it ends with r133g2), the harder queue q133x (24-30 things a task), then two of
# the three waves again (r133b2, r133c2). Over the cloud; logs pulled only when on USB.
cd /e/AgentStorage/esp32/iphone-agent-build13/tools/device-test || exit 1
P="C:/Users/牛杰/AppData/Roaming/uv/tools/pymobiledevice3/Scripts/python.exe"
rm -f chain133x.stop chain133x.done
until [ -f chain133r.done ]; do sleep 20; done
mkdir -p logs_133
usb() { timeout 30 "$P" -m pymobiledevice3 usbmux list 2>/dev/null | grep -q Identifier; }
( while [ ! -f chain133x.stop ] && [ ! -f chain133x.done ]; do
    if usb && timeout 120 "$P" pulllog.py logs_133/tmp >/dev/null 2>&1; then
      mv logs_133/tmp/debug.log "logs_133/debug-$(date +%m%d-%H%M%S).log"
    fi
    sleep 360
  done ) &
PULLER=$!
for w in q133x.json:r133x q130b.json:r133b2 q130c.json:r133c2; do
  [ -f chain133x.stop ] && break
  q=${w%%:*}; out=${w##*:}
  echo "$(date +%T) start $q -> $out"
  PYTHONIOENCODING=utf-8 py -3 cloudq.py "$q" "$out" > "cloudq_$out.log" 2>&1
  echo QDONE >> "cloudq_$out.log"
  if usb; then
    timeout 120 "$P" pulllog.py "$out/logs_end" >/dev/null 2>&1; timeout 120 "$P" pulllog1.py "$out/logs_end" >/dev/null 2>&1
  fi
  echo "$(date +%T) done $out"
done
touch chain133x.done
kill $PULLER 2>/dev/null
echo "$(date +%T) chain over"
