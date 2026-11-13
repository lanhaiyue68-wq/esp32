#!/bin/bash
# chain128.sh: after round 1 (cloudq128g.log QDONE), keep its logs, wait for the phone to be idle, run round 2 (r128g2).
cd /e/AgentStorage/esp32/iphone-agent-build13/tools/device-test || exit 1
P="C:/Users/牛杰/AppData/Roaming/uv/tools/pymobiledevice3/Scripts/python.exe"
USB=D:/AIProjects/agent-toolbox/iphone-logs/lan_usb.py
until grep -q QDONE cloudq128g.log; do sleep 30; done
echo "$(date +%T) round 1 QDONE"
mkdir -p r128g/logs_end
"$P" pulllog.py r128g/logs_end >/dev/null 2>&1; "$P" pulllog1.py r128g/logs_end >/dev/null 2>&1
ls -la r128g/logs_end
for i in $(seq 1 40); do
  s=$("$P" $USB status 2>/dev/null | head -c 200)
  case "$s" in *'"running": false'*) echo "$(date +%T) phone idle"; break;; esac
  sleep 30
done
curl -s -o /dev/null -w "mock %{http_code}\n" http://127.0.0.1:8787/ || echo "mock unreachable"
sleep 20
echo "$(date +%T) round 2 start"
PYTHONIOENCODING=utf-8 py -3 cloudq.py q128g.json r128g2 > cloudq128g2.log 2>&1
echo "$(date +%T) round 2 exit $?"; echo QDONE >> cloudq128g2.log
"$P" pulllog.py r128g2/logs_end >/dev/null 2>&1; "$P" pulllog1.py r128g2/logs_end >/dev/null 2>&1; ls -la r128g2/logs_end
