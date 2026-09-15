#!/usr/bin/env bash
set -euo pipefail

helper="$(cd "$(dirname "$0")" && pwd)/delegation-check.sh"
scratch="$(mktemp -d "${TMPDIR:-/tmp}/codex-loop-delegation-test.XXXXXX")"
trap 'rm -rf -- "$scratch"' EXIT

sessions_root="$scratch/telemetry with spaces/sessions"
sessions="$sessions_root/2026/01/01"
mkdir -p "$sessions"
run_dir="$scratch/run"
mkdir "$run_dir"

parent=01a00000-0000-7000-8000-000000000001
other=01a00000-0000-7000-8000-000000000002

run_helper() {
  local round="${1:-1}"
  bash "$helper" "$run_dir" "$round" "$run_dir/round-$round.log" "${2:-$sessions_root}"
}

# write_rollout NAME PARENT DEPTH PATH [EFFORT [CMD...]]
write_rollout() {
  local name="$1" parent_id="$2" depth="$3" path="$4" effort="${5:-}"
  shift 4; [[ $# -gt 0 ]] && shift
  local file="$sessions/rollout-$name.jsonl"
  printf '{"timestamp":"2026-01-01T10:00:00.000Z","type":"session_meta","payload":{"id":"%s","source":{"subagent":{"thread_spawn":{"parent_thread_id":"%s","depth":%s,"agent_path":"%s"}}}}}\n' \
    "$name" "$parent_id" "$depth" "$path" > "$file"
  if [[ -n "$effort" ]]; then
    printf '{"timestamp":"2026-01-01T10:00:01.000Z","type":"turn_context","payload":{"model":"m","effort":"%s"}}\n' "$effort" >> "$file"
  fi
  local cmd
  for cmd in "$@"; do
    printf '{"timestamp":"2026-01-01T10:00:30.000Z","type":"response_item","payload":{"type":"custom_tool_call","name":"exec","input":"text(await tools.exec_command({cmd:\\"%s\\"}));"}}\n' "$cmd" >> "$file"
  done
  printf '{"timestamp":"2026-01-01T10:01:00.500Z","type":"event_msg","payload":{"type":"noise","parent_thread_id":"%s"}}\n' "$parent_id" >> "$file"
}

write_rollout c1 "$parent" 1 /root/correctness medium 'git diff --cached --stat' 'git diff --cached' 'cat AGENTS.md'
printf '{"type":"turn_context","payload":{"effort":"xhigh"}}\n' >> "$sessions/rollout-c1.jsonl"
write_rollout c2 "$parent" 1 /root/contracts xhigh 'git diff --cached --stat && git diff --cached --name-only' 'rg -n foo src'
write_rollout c3 c1 2 /root/correctness/helper medium "cat $run_dir/staged.diff"
write_rollout x1 "$other" 1 /root/unrelated
printf '{"type":"session_meta","payload":{"id":"%s","source":"exec"}}\n' "$parent" > "$sessions/rollout-root.jsonl"

sleep 1
printf 'OpenAI Codex v0.0.0\nsession id: %s\nuser\n' "$parent" > "$run_dir/round-1.log"

output="$(run_helper)"
expected="delegation: session=$parent children=3 depth1=2 full_diff=2 effort=medium,xhigh
  1 /root/contracts calls=2 secs=60 diff=no effort=xhigh rollout=$sessions/rollout-c2.jsonl
  1 /root/correctness calls=3 secs=60 diff=yes effort=medium,xhigh rollout=$sessions/rollout-c1.jsonl
  2 /root/correctness/helper calls=1 secs=60 diff=yes effort=medium rollout=$sessions/rollout-c3.jsonl"
[[ "$output" == "$expected" ]] || {
  echo "test-delegation-check: unexpected output:" >&2
  printf '%s\n' "$output" >&2
  echo "expected:" >&2
  printf '%s\n' "$expected" >&2
  exit 1
}

# A rollout written after the log is not this attempt's child.
sleep 1
write_rollout late "$parent" 1 /root/late
output="$(run_helper)"
[[ "$output" == "$expected" ]] || {
  echo "test-delegation-check: late rollout was counted" >&2
  exit 1
}

# Missing sessions directory reports unknown with exit 2.
set +e
run_helper 1 "$scratch/missing" > "$scratch/unknown.out" 2>/dev/null
status=$?
set -e
[[ "$status" == 2 ]] || { echo "test-delegation-check: expected exit 2, got $status" >&2; exit 1; }
grep -q 'children=unknown' "$scratch/unknown.out"

# A log without a session id fails.
printf 'no header\n' > "$run_dir/round-2.log"
if run_helper 2 > /dev/null 2>&1; then
  echo "test-delegation-check: expected failure for missing session id" >&2
  exit 1
fi

# No matching descendants is a valid count, not a parsing failure.
printf 'session id: 01a00000-0000-7000-8000-000000000099\n' > "$run_dir/round-3.log"
output="$(run_helper 3)"
[[ "$output" == *'children=0 depth1=0 full_diff=0 effort=none' ]] || exit 1

# Missing effort on a later turn must not be hidden by the first turn's value.
printf '{"type":"turn_context","payload":{}}\n' >> "$sessions/rollout-c3.jsonl"
printf 'session id: %s\n' "$parent" > "$run_dir/round-4.log"
output="$(run_helper 4)"
[[ "$output" == *'/root/correctness/helper calls=1 secs=60 diff=yes effort=medium,unknown'* ]] || exit 1

echo "test-delegation-check: ok"
