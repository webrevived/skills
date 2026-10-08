#!/usr/bin/env bash
set -euo pipefail

scripts="$(cd "$(dirname "$0")" && pwd)"
scratch="$(mktemp -d "${TMPDIR:-/tmp}/codex-loop-validate-test.XXXXXX")"
trap 'rm -rf -- "$scratch"' EXIT

fail() {
  echo "test-validate-outcome: $*" >&2
  exit 1
}

sessions="$scratch/sessions/2026/01/01"
mkdir -p "$sessions"
parent=01a00000-0000-7000-8000-0000000000aa

child() { # child NAME DEPTH PARENT EFFORT
  printf '{"timestamp":"2026-01-01T10:00:00.000Z","type":"session_meta","payload":{"id":"%s","source":{"subagent":{"thread_spawn":{"parent_thread_id":"%s","depth":%s,"agent_path":"/root/%s"}}}}}\n{"type":"turn_context","payload":{"effort":"%s"}}\n' \
    "$1" "$3" "$2" "$1" "$4" > "$sessions/rollout-$1.jsonl"
}

new_run() { # new_run LEVEL
  local run
  run="$(mktemp -d "$scratch/run.XXXXXX")"
  printf '%s\n' "$1" > "$run/review-level"
  bash "$scripts/round-budget.sh" init "$run" 3
  printf '%s\n' "$run"
}

result() { # result RUN ROUND JSON
  printf '%s\n' "$3" > "$1/round-$2.json"
  printf '0\n' > "$1/round-$2.exit"
  printf 'session id: %s\n' "$parent" > "$1/round-$2.log"
}

expect() { # expect STATUS DESCRIPTION CMD...
  local want="$1" what="$2"; shift 2
  set +e; "$@" > "$scratch/last.out" 2>&1; local got=$?; set -e
  [[ "$got" == "$want" ]] || { cat "$scratch/last.out" >&2; fail "$what: expected exit $want, got $got"; }
}

for i in 1 2 3 4; do child "finder_$i" 1 "$parent" medium; done
child verify_batch_1 1 "$parent" medium
sleep 1

cov='{"finders":4,"verifier_batches":1,"dedicated_verifiers":0,"candidates_assigned":3,"candidates_checked":3}'
finding='{"id":"F1","title":"t","file":"a.ts","line":3,"severity":"major","category":"correctness","validation":"confirmed","failure_scenario":"s","body":"b","repeat_of":""}'

# Valid medium round 1 with one finding.
run="$(new_run medium)"
result "$run" 1 "{\"verdict\":\"findings\",\"summary\":\"s\",\"coverage\":$cov,\"findings\":[$finding],\"unchecked_candidates\":[]}"
expect 0 "valid round 1" bash "$scripts/validate.sh" "$run" "$scratch/sessions"
[[ -e "$run/round-1.valid" ]] || fail "valid marker missing"

# Applied fix not yet verified => open.
printf '{"round":1,"dispositions":[{"id":"F1","disposition":"accepted","note":"n"}],"questions":[],"checks":[]}\n' > "$run/dispositions-1.json"
[[ "$(bash "$scripts/outcome.sh" "$run")" == outcome=open* ]] || fail "unverified fix should be open"

# Clean verification round => clean.
bash "$scripts/round-budget.sh" advance "$run"
result "$run" 2 '{"verdict":"clean","summary":"s","coverage":{"finders":0,"verifier_batches":0,"dedicated_verifiers":0,"candidates_assigned":0,"candidates_checked":0},"findings":[],"unchecked_candidates":[]}'
expect 0 "valid round 2" bash "$scripts/validate.sh" "$run"
[[ "$(bash "$scripts/outcome.sh" "$run")" == outcome=clean* ]] || fail "verified round should be clean"
touch "$run/round-1-attempt-1.valid"   # archived attempts must not be read as rounds
[[ "$(bash "$scripts/outcome.sh" "$run")" == outcome=clean* ]] || fail "archived attempt broke outcome"
[[ "$(bash "$scripts/outcome.sh" "$run" --stop stalemate)" == outcome=escalate* ]] || fail "stalemate should escalate"

# Unknown repeat_of is invalid.
bash "$scripts/round-budget.sh" advance "$run"
result "$run" 3 "{\"verdict\":\"findings\",\"summary\":\"s\",\"coverage\":{\"finders\":0,\"verifier_batches\":0,\"dedicated_verifiers\":0,\"candidates_assigned\":0,\"candidates_checked\":0},\"findings\":[${finding/\"repeat_of\":\"\"/\"repeat_of\":\"R9-F9\"}],\"unchecked_candidates\":[]}"
expect 1 "unknown repeat_of" bash "$scripts/validate.sh" "$run"

# Coverage that disagrees with telemetry, wrong finder count, contradictory verdict.
run="$(new_run medium)"
result "$run" 1 "{\"verdict\":\"clean\",\"summary\":\"s\",\"coverage\":${cov/\"verifier_batches\":1/\"verifier_batches\":2},\"findings\":[],\"unchecked_candidates\":[]}"
expect 1 "telemetry mismatch" bash "$scripts/validate.sh" "$run" "$scratch/sessions"
run="$(new_run high)"
result "$run" 1 "{\"verdict\":\"clean\",\"summary\":\"s\",\"coverage\":$cov,\"findings\":[],\"unchecked_candidates\":[]}"
expect 1 "high needs 8 finders" bash "$scripts/validate.sh" "$run" "$scratch/sessions"
run="$(new_run medium)"
result "$run" 1 "{\"verdict\":\"clean\",\"summary\":\"s\",\"coverage\":$cov,\"findings\":[$finding],\"unchecked_candidates\":[]}"
expect 1 "clean with findings" bash "$scripts/validate.sh" "$run" "$scratch/sessions"

# Unchecked candidates keep the run open even after rejection-only dispositions.
run="$(new_run medium)"
cand='{"id":"C1","file":"a.ts","line":1,"summary":"s","reason":"verification_incomplete"}'
result "$run" 1 "{\"verdict\":\"incomplete\",\"summary\":\"s\",\"coverage\":${cov/\"candidates_checked\":3/\"candidates_checked\":2},\"findings\":[$finding],\"unchecked_candidates\":[$cand]}"
expect 0 "incomplete is a valid result" bash "$scripts/validate.sh" "$run" "$scratch/sessions"
printf '{"round":1,"dispositions":[{"id":"F1","disposition":"rejected","note":"n"}],"questions":[],"checks":[]}\n' > "$run/dispositions-1.json"
[[ "$(bash "$scripts/outcome.sh" "$run")" == outcome=open*unchecked=1* ]] || fail "unchecked candidates should keep the run open"

# Questions escalate; telemetry unavailable is exit 2; failed codex exit is invalid.
printf '{"round":1,"dispositions":[],"questions":[{"id":"F1","question":"q"}],"checks":[]}\n' > "$run/dispositions-1.json"
[[ "$(bash "$scripts/outcome.sh" "$run")" == outcome=escalate* ]] || fail "questions should escalate"
run="$(new_run medium)"
result "$run" 1 "{\"verdict\":\"clean\",\"summary\":\"s\",\"coverage\":$cov,\"findings\":[],\"unchecked_candidates\":[]}"
expect 2 "missing telemetry" bash "$scripts/validate.sh" "$run" "$scratch/nowhere"
printf '1\n' > "$run/round-1.exit"
expect 1 "nonzero codex exit" bash "$scripts/validate.sh" "$run" "$scratch/sessions"
[[ "$(bash "$scripts/outcome.sh" "$run")" == outcome=open*rounds=0* ]] || fail "no valid round should be open"

echo "test-validate-outcome: ok"
