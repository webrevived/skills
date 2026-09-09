#!/usr/bin/env bash
set -euo pipefail

# Counts the child agent threads a `codex exec` review session actually spawned.
#
# The human-readable `codex exec` log and its `--json` stream never print `spawn_agent`
# calls, so the only durable evidence of delegation is the child rollout files Codex writes
# under `$CODEX_HOME/sessions`. Each child rollout starts with a `session_meta` line whose
# `source.subagent.thread_spawn.parent_thread_id` names the parent session.
#
# usage: delegation-check.sh RUN_DIR ROUND [LOG_PATH]
#
# stdout: `delegation: session=<id> children=<n> depth1=<n>` followed by one
#         `<depth> <agent_path>` line per child.
# exit 0: counted (children may be zero)
# exit 1: usage or the log has no session id
# exit 2: sessions directory unavailable; delegation is unknown, not absent

fail() {
  echo "delegation-check: $*" >&2
  exit 1
}

[[ $# == 2 || $# == 3 ]] || fail "usage: delegation-check.sh RUN_DIR ROUND [LOG_PATH]"

run_dir="$1"
round="$2"
log_path="${3:-$run_dir/round-$round.log}"

[[ -d "$run_dir" ]] || fail "run directory does not exist: $run_dir"
[[ "$round" =~ ^[1-9][0-9]*$ ]] || fail "round must be a positive integer"
[[ -f "$log_path" ]] || fail "missing review log: $log_path"
command -v jq > /dev/null || fail "jq is required"

session_id="$(sed -n 's/^session id: \([0-9a-fA-F-]*\)$/\1/p' "$log_path" | head -n 1)"
[[ -n "$session_id" ]] || fail "no session id header in $log_path"

sessions_dir="${CODEX_HOME:-$HOME/.codex}/sessions"
if [[ ! -d "$sessions_dir" ]]; then
  echo "delegation-check: sessions directory unavailable: $sessions_dir" >&2
  echo "delegation: session=$session_id children=unknown depth1=unknown"
  exit 2
fi

# Child rollouts are written while the review runs, so they are never newer than the final
# log write. Bound the scan to the last two days and to files not newer than the log so an
# archived attempt log still resolves its own children.
find_args=(-mtime -2 ! -newer "$log_path")

children=0
depth1=0
lines=()
while IFS= read -r -d '' rollout; do
  grep -q -F "\"parent_thread_id\":\"$session_id\"" "$rollout" || continue
  child="$(head -n 1 "$rollout" | jq -r --arg sid "$session_id" '
    (.payload.source.subagent.thread_spawn // empty)
    | select(.parent_thread_id == $sid)
    | "\(.depth) \(.agent_path)"' 2>/dev/null || true)"
  [[ -n "$child" ]] || continue
  children=$((children + 1))
  [[ "$child" == 1\ * ]] && depth1=$((depth1 + 1))
  lines+=("$child")
done < <(find "$sessions_dir" -type f -name 'rollout-*.jsonl' "${find_args[@]}" -print0)

echo "delegation: session=$session_id children=$children depth1=$depth1"
if (( ${#lines[@]} > 0 )); then
  printf '  %s\n' "${lines[@]}" | sort
fi
