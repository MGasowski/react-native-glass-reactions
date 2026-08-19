#!/usr/bin/env bash
# Drives the Maestro flow against a booted emulator in CI.
#
# This lives in a file rather than inline in the workflow because the
# emulator action runs each line of `script:` in its own shell — a bare
# `cd` on one line does not carry to the next, which is how the first
# attempt failed with "./gradlew: not found".
set -euo pipefail

echo "--- installing debug build"
(cd example/android && ./gradlew installDebug)

echo "--- starting Metro"
# The debug build fetches its JS bundle at launch, so Metro has to be
# serving before Maestro opens the app or the flow meets a red box.
yarn example start >/tmp/metro-ci.log 2>&1 &
METRO_PID=$!
trap 'kill "$METRO_PID" 2>/dev/null || true' EXIT

adb reverse tcp:8081 tcp:8081

echo "--- waiting for Metro"
for _ in $(seq 1 60); do
  if curl -sf http://localhost:8081/status >/dev/null 2>&1; then
    echo "Metro ready"
    break
  fi
  sleep 2
done
curl -sf http://localhost:8081/status >/dev/null 2>&1 || {
  echo "Metro never became ready; last log:"; tail -30 /tmp/metro-ci.log; exit 1
}

echo "--- running Maestro flow"
maestro test .maestro/reactions.yaml
