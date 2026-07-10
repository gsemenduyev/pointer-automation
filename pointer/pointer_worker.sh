#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CONFIG_PATH="$SCRIPT_DIR/pointer_config.sh"
MOUSE_MOVER_SRC="$SCRIPT_DIR/mouse_mover.swift"
MOUSE_MOVER_BIN="$SCRIPT_DIR/.mouse_mover"
MOUSE_WARNING_SHOWN=0

if [ ! -f "$CONFIG_PATH" ]; then
  echo "Error: missing config file at $CONFIG_PATH" >&2
  exit 1
fi

# shellcheck disable=SC1090
source "$CONFIG_PATH"

TOTAL_TIME_MINUTES="${TOTAL_TIME_MINUTES:-0}"
INTERVAL_SECONDS="${INTERVAL_SECONDS:-0}"
MOUSE_MOVE_MODE="${MOUSE_MOVE_MODE:-small}"
MOVE_DISTANCE_PIXELS="${MOVE_DISTANCE_PIXELS:-120}"

if ! [[ "$TOTAL_TIME_MINUTES" =~ ^[0-9]+([.][0-9]+)?$ ]]; then
  echo "Error: TOTAL_TIME_MINUTES must be a non-negative number." >&2
  exit 1
fi

if awk "BEGIN { exit !($TOTAL_TIME_MINUTES > 0) }"; then
  :
else
  echo "Error: set TOTAL_TIME_MINUTES > 0." >&2
  exit 1
fi

TOTAL_TIME_SECONDS="$(awk -v m="$TOTAL_TIME_MINUTES" 'BEGIN { s=m*60; print int((s == int(s)) ? s : s+1) }')"

if ! [[ "$INTERVAL_SECONDS" =~ ^[0-9]+$ ]] || [ "$INTERVAL_SECONDS" -lt 1 ]; then
  echo "Error: INTERVAL_SECONDS must be a positive integer." >&2
  exit 1
fi

if [ "$MOUSE_MOVE_MODE" != "small" ] && [ "$MOUSE_MOVE_MODE" != "large" ]; then
  echo "Error: MOUSE_MOVE_MODE must be 'small' or 'large'." >&2
  exit 1
fi

if ! [[ "$MOVE_DISTANCE_PIXELS" =~ ^[0-9]+$ ]] || [ "$MOVE_DISTANCE_PIXELS" -lt 1 ]; then
  echo "Error: MOVE_DISTANCE_PIXELS must be a positive integer." >&2
  exit 1
fi

warn_mouse_backend() {
  if [ "$MOUSE_WARNING_SHOWN" -eq 0 ]; then
    echo "Warning: pointer movement backend is blocked or unavailable." >&2
    echo "Allow Accessibility and Input Monitoring permissions for PointerAutomation/Terminal." >&2
    MOUSE_WARNING_SHOWN=1
  fi
}

if [ ! -f "$MOUSE_MOVER_SRC" ]; then
  warn_mouse_backend
  exit 1
fi

if [ ! -x "$MOUSE_MOVER_BIN" ] || [ "$MOUSE_MOVER_SRC" -nt "$MOUSE_MOVER_BIN" ]; then
  if ! swiftc "$MOUSE_MOVER_SRC" -O -o "$MOUSE_MOVER_BIN" >/dev/null 2>&1; then
    warn_mouse_backend
    exit 1
  fi
fi

TOTAL_STEPS=$(((TOTAL_TIME_SECONDS + INTERVAL_SECONDS - 1) / INTERVAL_SECONDS))
elapsed=0
step=0
small_direction="right"

while [ "$elapsed" -lt "$TOTAL_TIME_SECONDS" ]; do
  remaining=$((TOTAL_TIME_SECONDS - elapsed))
  sleep_for="$INTERVAL_SECONDS"

  if [ "$remaining" -lt "$INTERVAL_SECONDS" ]; then
    sleep_for="$remaining"
  fi

  step=$((step + 1))
  if [ "$MOUSE_MOVE_MODE" = "small" ]; then
    echo "[${step}/${TOTAL_STEPS}] waiting ${sleep_for}s"
    sleep "$sleep_for"
    elapsed=$((elapsed + sleep_for))

    echo "[${step}/${TOTAL_STEPS}] moving pointer (small, ${small_direction})"
    if ! "$MOUSE_MOVER_BIN" "$MOUSE_MOVE_MODE" "$MOVE_DISTANCE_PIXELS" "$sleep_for" "$small_direction" >/dev/null 2>&1; then
      warn_mouse_backend
    fi

    if [ "$small_direction" = "right" ]; then
      small_direction="left"
    else
      small_direction="right"
    fi
  else
    echo "[${step}/${TOTAL_STEPS}] waiting ${sleep_for}s"
    sleep "$sleep_for"
    elapsed=$((elapsed + sleep_for))

    echo "[${step}/${TOTAL_STEPS}] moving pointer (${MOUSE_MOVE_MODE})"
    if ! "$MOUSE_MOVER_BIN" "$MOUSE_MOVE_MODE" "$MOVE_DISTANCE_PIXELS" "$sleep_for" >/dev/null 2>&1; then
      warn_mouse_backend
    fi
  fi
done

echo "done"
