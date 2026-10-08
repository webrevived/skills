#!/usr/bin/env bash
set -euo pipefail

# Blocks until the current round's review attempt exits, for at most MAX_SECONDS (default 540,
# under a 10-minute tool timeout). Call it repeatedly; it never starts or stops anything.
#
# usage: wait.sh RUN_DIR [MAX_SECONDS]
# exit 0: attempt finished (prints its codex exit status); 75: still running

[[ $# -ge 1 && -d "$1" ]] || { echo "usage: wait.sh RUN_DIR [MAX_SECONDS]" >&2; exit 1; }
run="$1"
max="${2:-540}"
n="$(bash "$(dirname "$0")/round-budget.sh" current "$run")"

# exit 1: review.sh died without recording a status
waited=0
dead=0
until [[ -s "$run/round-$n.exit" ]]; do
  pid="$(cat "$run/round-$n.pid" 2> /dev/null || true)"
  if [[ -n "$pid" ]] && ! kill -0 "$pid" 2> /dev/null; then
    dead=$((dead + 5))
    if (( dead >= 20 )); then
      echo "wait: codex pid $pid exited but review.sh recorded no status; treat the attempt as failed" >&2
      exit 1
    fi
  fi
  if (( waited >= max )); then
    echo "wait: round $n still running after ${waited}s; call again"
    exit 75
  fi
  sleep 5
  waited=$((waited + 5))
done
echo "wait: round $n finished, codex exit=$(cat "$run/round-$n.exit")"
