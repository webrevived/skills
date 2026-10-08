#!/usr/bin/env bash
set -euo pipefail

# Starts one Codex review attempt for the current round. Run it in the foreground: it checks the
# budget and inputs, archives any previous attempt, assembles the prompt, launches a detached
# runner (codex + watchdog), and returns once the runner is up. Then block on wait.sh.
#
# usage: review.sh RUN_DIR
# The runner writes round-N.{json,log,pid,exit} (exit holds codex's status; 124 = watchdog).
# exit 0: launched; 3: round budget exhausted; 1: precondition failure (nothing launched)

fail() {
  echo "review: $*" >&2
  exit 1
}

mode=prepare
if [[ "${1:-}" == --runner ]]; then
  mode=runner
  shift
fi
[[ $# == 1 && -d "$1" ]] || fail "usage: review.sh RUN_DIR"
run="$(cd "$1" && pwd)"
skill_dir="$(cd "$(dirname "$0")/.." && pwd)"
refs="$skill_dir/references"
level="$(cat "$run/review-level")"
case "$level" in
  medium) deadline=$((45 * 60)) ;;
  high) deadline=$((60 * 60)) ;;
  *) fail "invalid saved review level: $level" ;;
esac
n="$(bash "$skill_dir/scripts/round-budget.sh" current "$run")"
prompt="$run/prompt-$n.md"

prepare() {
  bash "$skill_dir/scripts/round-budget.sh" guard "$run" > /dev/null || exit 3

  # Archive a previous attempt so stale output can never pass as this attempt's result.
  if compgen -G "$run/round-$n.*" > /dev/null; then
    local attempt=1 f
    while compgen -G "$run/round-$n-attempt-$attempt.*" > /dev/null; do attempt=$((attempt + 1)); done
    for f in "$run/round-$n".*; do mv "$f" "$run/round-$n-attempt-$attempt.${f##*/round-$n.}"; done
  fi

  local required=("$run/pins" "$run/snap-0" "$run/review.diff") prev=$((n - 1)) f
  if [[ "$n" != 1 ]]; then
    required+=("$run/round-$prev.json" "$run/dispositions-$prev.json" "$run/snap-$prev")
  fi
  for f in "${required[@]}"; do
    [[ -s "$f" ]] || fail "missing $f; run snapshot.sh and the fixer before reviewing round $n"
  done

  {
    cat "$refs/review-prompt.md"
    printf '\n## Review level\n\n%s\n' "$level"
    if [[ "$n" == 1 ]]; then
      cat "$refs/initial-review-protocol.md"
      printf '\n## Review input\n\n- Diff file: %s\n- Base commit: %s\n- Reviewed tree (S0): %s\n' \
        "$run/review.diff" "$(sed -n 's/^base=//p' "$run/pins")" "$(cat "$run/snap-0")"
    else
      cat "$refs/verification-prompt.md"
      printf '\n## Review input\n\n- Prior findings: %s\n- Prior dispositions: %s\n' "$run/round-$prev.json" "$run/dispositions-$prev.json"
      printf -- '- Latest fixes (round %s): %s\n- Cumulative fixes since S0: %s\n' "$prev" "$run/fixes-latest-$prev.diff" "$run/fixes-cumulative-$prev.diff"
      printf -- '- Original reviewed input: %s\n- Current tree (S%s): %s\n' "$run/review.diff" "$prev" "$(cat "$run/snap-$prev")"
    fi
    if [[ -s "$run/focus.md" ]]; then
      printf '\n## Additional focus\n\n'
      cat "$run/focus.md"
    fi
  } > "$prompt"

  # Detach so the attempt outlives this call; the caller learns launch failures synchronously.
  nohup bash "$0" --runner "$run" > /dev/null 2>&1 < /dev/null &
  disown
  local _
  for _ in $(seq 50); do
    if [[ -s "$run/round-$n.pid" || -s "$run/round-$n.exit" ]]; then
      echo "review: round $n launched"
      exit 0
    fi
    sleep 0.2
  done
  fail "runner did not start within 10s"
}

run_codex() {
  local log="$run/round-$n.log" pid status elapsed=0 _
  codex exec -C "$(cat "$run/repo")" \
    -m "$(cat "$run/model")" -c "model_reasoning_effort=\"$level\"" \
    -c "agents.default_subagent_reasoning_effort=\"$level\"" \
    -c agents.max_concurrent_threads_per_session=12 \
    -c memories.use_memories=false \
    -s read-only \
    --output-schema "$refs/findings.schema.json" \
    -o "$run/round-$n.json" \
    - < "$prompt" > "$log" 2>&1 &
  pid=$!
  printf '%s\n' "$pid" > "$run/round-$n.pid"

  while kill -0 "$pid" 2> /dev/null; do
    if (( elapsed >= deadline )); then
      echo "review: watchdog deadline (${deadline}s) reached; terminating codex pid $pid" >> "$log"
      kill -TERM "$pid" 2> /dev/null || true
      for _ in $(seq 30); do kill -0 "$pid" 2> /dev/null || break; sleep 1; done
      kill -KILL "$pid" 2> /dev/null || true
      wait "$pid" 2> /dev/null || true
      printf '124\n' > "$run/round-$n.exit"
      return
    fi
    sleep 5
    elapsed=$((elapsed + 5))
  done

  set +e
  wait "$pid"
  status=$?
  set -e
  printf '%s\n' "$status" > "$run/round-$n.exit"
}

if [[ "$mode" == runner ]]; then
  run_codex
else
  prepare
fi
