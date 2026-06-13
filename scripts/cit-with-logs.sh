#!/bin/sh
# Wraps `dbuild test` with automatic full log capture.
# On failure, the real stack trace is in cit-output.log (not dbuild's truncated tail).
# On success, writes a .cit-passed marker so the enforce-cit hook allows PRs.
#
# Usage: scripts/cit-with-logs.sh [--variant TAG]
#
# Requires: dbuild, podman

set -e

VARIANT="latest"
case "$1" in
  --variant) VARIANT="$2"; shift 2 ;;
esac

IMAGE_NAME=$(basename "$(pwd)")
LOG_FILE="cit-output.log"
MARKER=".cit-passed"

# Clean previous state
rm -f "$LOG_FILE" "$MARKER"

echo "[cit] Starting dbuild test (variant: $VARIANT) with log capture..."

# Run dbuild test in background
dbuild --variant "$VARIANT" test >"${LOG_FILE}.dbuild" 2>&1 &
DBUILD_PID=$!

# Wait for the CIT container to appear (up to 30s)
CIT_CONTAINER=""
for i in $(seq 1 30); do
  CIT_CONTAINER=$(podman ps --format '{{.Names}}' 2>/dev/null | grep -iE "cit.*${IMAGE_NAME}|${IMAGE_NAME}.*cit" | head -1)
  if [ -n "$CIT_CONTAINER" ]; then
    break
  fi
  sleep 1
done

if [ -n "$CIT_CONTAINER" ]; then
  echo "[cit] Found container: $CIT_CONTAINER — capturing logs..."

  # Wait for meaningful output (up to 120s)
  DEADLINE=$(($(date +%s) + 120))
  while [ "$(date +%s)" -lt "$DEADLINE" ]; do
    if podman logs "$CIT_CONTAINER" 2>&1 | grep -qiE "Migrations|Starting|Error|listening|startup complete|ready" 2>/dev/null; then
      break
    fi
    sleep 2
  done

  # Capture full logs (filter kevent noise)
  podman logs "$CIT_CONTAINER" 2>&1 | grep -ivE "kevent\(\)" > "$LOG_FILE" 2>/dev/null || true
  echo "[cit] Logs written to $LOG_FILE"
else
  echo "[cit] WARNING: could not find CIT container — logs not captured"
fi

# Wait for dbuild test to finish
wait "$DBUILD_PID"
RESULT=$?

echo ""
cat "${LOG_FILE}.dbuild"
rm -f "${LOG_FILE}.dbuild"

if [ "$RESULT" -eq 0 ]; then
  echo ""
  echo "[cit] CIT PASSED"
  date -u '+%Y-%m-%dT%H:%M:%SZ' > "$MARKER"
  exit 0
else
  echo ""
  echo "[cit] CIT FAILED — full logs in $LOG_FILE:"
  echo "---"
  cat "$LOG_FILE" 2>/dev/null || echo "(no logs captured)"
  echo "---"
  exit 1
fi
