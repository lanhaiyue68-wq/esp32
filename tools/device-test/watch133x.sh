#!/bin/bash
# watch133.sh: wakes the session when the mock cloud hears nothing from the phone for 20 minutes while the chain runs
# (a running task reports every ~15 s). Needs no USB.
cd /e/AgentStorage/esp32/iphone-agent-build13/tools/device-test || exit 1
while [ ! -f chain133x.done ] && [ ! -f chain133x.stop ] && [ ! -f watch133.stop ]; do
  age=$(( $(date +%s) - $(stat -c %Y mock_cloud_132.log) ))
  if [ $age -ge 1200 ]; then echo "$(date +%T) cloud quiet ${age}s; usb: $(timeout 30 "C:/Users/牛杰/AppData/Roaming/uv/tools/pymobiledevice3/Scripts/python.exe" -m pymobiledevice3 usbmux list 2>/dev/null | grep -c Identifier)"; exit 3; fi
  sleep 120
done
echo "$(date +%T) chain over"
