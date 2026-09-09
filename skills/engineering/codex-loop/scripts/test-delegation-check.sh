#!/usr/bin/env bash
set -euo pipefail

helper="$(cd "$(dirname "$0")" && pwd)/delegation-check.sh"
scratch="$(mktemp -d "${TMPDIR:-/tmp}/codex-loop-delegation-test.XXXXXX")"
trap 'rm -rf -- "$scratch"' EXIT

export CODEX_HOME="$scratch/codex-home"
sessions="$CODEX_HOME/sessions/2026/01/01"
mkdir -p "$sessions"
run_dir="$scratch/run"
mkdir "$run_dir"

parent=01a00000-0000-7000-8000-000000000001
other=01a00000-0000-7000-8000-000000000002

write_rollout() {
  local name="$1" parent_id="$2" depth="$3" path="$4"
  printf '{"type":"session_meta","payload":{"id":"%s","source":{"subagent":{"thread_spawn":{"parent_thread_id":"%s","depth":%s,"agent_path":"%s"}}}}}\n' \
    "$name" "$parent_id" "$depth" "$path" > "$sessions/rollout-$name.jsonl"
  printf '{"type":"event_msg","payload":{"type":"noise","parent_thread_id":"%s"}}\n' "$parent_id" >> "$sessions/rollout-$name.jsonl"
}

write_rollout c1 "$parent" 1 /root/correctness
write_rollout c2 "$parent" 1 /root/contracts
write_rollout c3 "$parent" 2 /root/correctness/helper
write_rollout x1 "$other" 1 /root/unrelated
printf '{"type":"session_meta","payload":{"id":"%s","source":"exec"}}\n' "$parent" > "$sessions/rollout-root.jsonl"

sleep 1
printf 'OpenAI Codex v0.0.0\nsession id: %s\nuser\n' "$parent" > "$run_dir/round-1.log"

output="$(bash "$helper" "$run_dir" 1)"
expected=$'delegation: session='"$parent"$' children=3 depth1=2\n  1 /root/contracts\n  1 /root/correctness\n  2 /root/correctness/helper'
[[ "$output" == "$expected" ]] || {
  echo "test-delegation-check: unexpected output:" >&2
  printf '%s\n' "$output" >&2
  exit 1
}

# A rollout written after the log is not this attempt's child.
sleep 1
write_rollout late "$parent" 1 /root/late
output="$(bash "$helper" "$run_dir" 1)"
[[ "$output" == "$expected" ]] || {
  echo "test-delegation-check: late rollout was counted" >&2
  exit 1
}

# Missing sessions directory reports unknown with exit 2.
set +e
CODEX_HOME="$scratch/missing" bash "$helper" "$run_dir" 1 > "$scratch/unknown.out" 2>/dev/null
status=$?
set -e
[[ "$status" == 2 ]] || { echo "test-delegation-check: expected exit 2, got $status" >&2; exit 1; }
grep -q 'children=unknown' "$scratch/unknown.out"

# A log without a session id fails.
printf 'no header\n' > "$run_dir/round-2.log"
if bash "$helper" "$run_dir" 2 > /dev/null 2>&1; then
  echo "test-delegation-check: expected failure for missing session id" >&2
  exit 1
fi

echo "test-delegation-check: ok"
