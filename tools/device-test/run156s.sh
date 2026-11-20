#!/bin/bash
# Short 156 check after the presentation session's screenshots: 3 tasks, 360 s each, none started after 08:13 Seoul (23:13 UTC).
cd /e/AgentStorage/esp32/iphone-agent-build13/tools/device-test || exit 1
for q in q156s/*.json; do
  [ "$(date -u +%H%M)" -ge 2313 ] && { echo "$(date +%T) cutoff, $q not started"; break; }
  echo "$(date +%T) start $q"
  PYTHONIOENCODING=utf-8 py -3 cloudq.py "$q" r156s >> cloudq_r156s.log 2>&1
  echo "$(date +%T) done $q"
  sleep 30
done
echo "$(date +%T) short check over"
