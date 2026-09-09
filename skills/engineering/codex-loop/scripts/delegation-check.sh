#!/usr/bin/env bash
set -euo pipefail

# Counts the child agent threads a `codex exec` review session actually spawned and measures
# how deeply each one worked.
#
# The human-readable `codex exec` log and its `--json` stream never print `spawn_agent`
# calls, so the only durable evidence of delegation is the child rollout files Codex writes
# under `$CODEX_HOME/sessions`. Each child rollout starts with a `session_meta` line whose
# `source.subagent.thread_spawn.parent_thread_id` names the parent session.
#
# usage: delegation-check.sh RUN_DIR ROUND [LOG_PATH]
#
# stdout: `delegation: session=<id> children=<n> depth1=<n> full_diff=<n> effort=<summary>`
#         followed by one `<depth> <agent_path> calls=<n> secs=<n> diff=<yes|no> effort=<e>`
#         line per child. `full_diff` counts children whose commands read the complete staged
#         diff (a `git diff --cached` without `--stat`/`--name-only`/`--check`, or the run's
#         `staged.diff` file). `effort` summarises the reasoning effort every child ran at.
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
  echo "delegation: session=$session_id children=unknown depth1=unknown full_diff=unknown effort=unknown"
  exit 2
fi

# Child rollouts are written while the review runs, so they are never newer than the final
# log write. Bound the scan to the last two days and to files not newer than the log so an
# archived attempt log still resolves its own children.
find_args=(-mtime -2 ! -newer "$log_path")

# Every tool-call payload a child sent, one per line, with newlines flattened.
child_calls() {
  jq -r '
    select(.type == "response_item"
      and (.payload.type == "function_call" or .payload.type == "custom_tool_call"))
    | (.payload.arguments // .payload.input // "")
    | tostring
    | gsub("[\r\n]+"; " ")' "$1" 2>/dev/null || true
}

# Whether the child read the complete staged diff rather than only its shape.
read_full_diff() {
  local calls="$1"
  grep -q -F 'staged.diff' <<< "$calls" && return 0
  sed -E 's/git diff --cached[[:space:]]+--(stat|name-only|name-status|numstat|check)[^;&|]*//g' <<< "$calls" \
    | grep -q -E 'git diff --cached' && return 0
  return 1
}

child_seconds() {
  jq -r -s '
    [.[] | .timestamp? // empty | sub("\\.[0-9]+Z$"; "Z") | fromdateiso8601?]
    | if length < 2 then 0 else (max - min) end' "$1" 2>/dev/null || echo 0
}

child_effort() {
  jq -r 'select(.type == "turn_context") | .payload.effort // empty' "$1" 2>/dev/null | head -n 1
}

children=0
depth1=0
full_diff=0
lines=()
efforts=()
while IFS= read -r -d '' rollout; do
  grep -q -F "\"parent_thread_id\":\"$session_id\"" "$rollout" || continue
  child="$(head -n 1 "$rollout" | jq -r --arg sid "$session_id" '
    (.payload.source.subagent.thread_spawn // empty)
    | select(.parent_thread_id == $sid)
    | "\(.depth) \(.agent_path)"' 2>/dev/null || true)"
  [[ -n "$child" ]] || continue
  children=$((children + 1))
  [[ "$child" == 1\ * ]] && depth1=$((depth1 + 1))

  calls="$(child_calls "$rollout")"
  call_count=0
  [[ -n "$calls" ]] && call_count="$(printf '%s\n' "$calls" | wc -l | tr -d ' ')"
  diff_flag=no
  if [[ -n "$calls" ]] && read_full_diff "$calls"; then
    diff_flag=yes
    full_diff=$((full_diff + 1))
  fi
  effort="$(child_effort "$rollout")"
  [[ -n "$effort" ]] || effort=unknown
  efforts+=("$effort")
  lines+=("$child calls=$call_count secs=$(child_seconds "$rollout") diff=$diff_flag effort=$effort")
done < <(find "$sessions_dir" -type f -name 'rollout-*.jsonl' "${find_args[@]}" -print0)

effort_summary=none
if (( ${#efforts[@]} > 0 )); then
  effort_summary="$(printf '%s\n' "${efforts[@]}" | sort -u | paste -sd, -)"
fi

echo "delegation: session=$session_id children=$children depth1=$depth1 full_diff=$full_diff effort=$effort_summary"
if (( ${#lines[@]} > 0 )); then
  printf '  %s\n' "${lines[@]}" | sort
fi
