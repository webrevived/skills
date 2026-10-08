#!/usr/bin/env bash
set -euo pipefail

# Accepts or rejects the current round's review attempt. Semantic checks the output schema
# cannot express, plus, for round 1, delegation coverage against Codex's own child telemetry.
#
# usage: validate.sh RUN_DIR [SESSIONS_DIR]
# exit 0: valid (writes round-N.valid)
# exit 1: invalid attempt (reasons on stderr); one retry within the round is allowed
# exit 2: delegation telemetry unavailable; coverage is unknown, which is never a success

run="${1:?usage: validate.sh RUN_DIR [SESSIONS_DIR]}"
scripts="$(cd "$(dirname "$0")" && pwd)"
n="$(bash "$scripts/round-budget.sh" current "$run")"
level="$(cat "$run/review-level")"
out="$run/round-$n.json"
log="$run/round-$n.log"
errors=()
err() { errors+=("$*"); }

finish() {
  if (( ${#errors[@]} > 0 )); then
    echo "validate: round $n invalid:" >&2
    printf '  - %s\n' "${errors[@]}" >&2
    [[ -f "$log" ]] && { echo "--- log tail" >&2; tail -n 15 "$log" >&2; }
    exit 1
  fi
  touch "$run/round-$n.valid"
  echo "validate: round $n valid"
  exit 0
}

status="$(cat "$run/round-$n.exit" 2> /dev/null || echo missing)"
[[ "$status" == 0 ]] || { err "codex exit status $status"; finish; }
jq -e 'type == "object"' "$out" > /dev/null 2>&1 || { err "missing or malformed JSON output"; finish; }

check() { # check JQ_EXPR MESSAGE
  jq -e "$1" "$out" > /dev/null || err "$2"
}
check '(.verdict == "incomplete") == ((.unchecked_candidates | length) > 0)' "incomplete must match unchecked_candidates"
check '.verdict == "incomplete" or ((.verdict == "findings") == ((.findings | length) > 0))' "verdict contradicts findings"
check '[.findings[].id] | (length == (unique | length)) and all(test("^F[1-9][0-9]*$"))' "finding ids not unique F1..Fn"
check '[.unchecked_candidates[].id] | length == (unique | length)' "duplicate unchecked candidate ids"
check 'all(.findings[]; .line >= 1)' "non-positive line"
grep -q 'agent thread limit reached' "$log" 2> /dev/null && err "reviewer hit the agent thread limit; coverage is not what the level promised"

if [[ "$n" == 1 ]]; then
  case "$level" in
    medium) finders=4 max_batches=3 max_assigned=18 ;;
    high) finders=8 max_batches=4 max_assigned=24 ;;
  esac
  check 'all(.findings[]; .repeat_of == "")' "round 1 findings cannot repeat"
  check ".coverage.finders == $finders" "expected $finders finders for $level"
  check ".coverage.verifier_batches <= $max_batches and .coverage.dedicated_verifiers <= 2" "verifier counts over budget"
  check ".coverage.candidates_assigned <= $max_assigned" "assigned candidates over cap"
  check '.coverage.candidates_checked + ([.unchecked_candidates[] | select(.reason == "verification_incomplete")] | length) == .coverage.candidates_assigned' "assigned candidates without a verdict are not reported unchecked"
  check '(.coverage.candidates_assigned == 0) == (.coverage.verifier_batches + .coverage.dedicated_verifiers == 0)' "verifiers must match assigned candidates"

  set +e
  bash "$scripts/delegation-check.sh" "$run" "$n" "$log" ${2:+"$2"} > "$run/delegation-$n.txt"
  dstatus=$?
  set -e
  header="$(head -n 1 "$run/delegation-$n.txt")"
  if [[ "$dstatus" == 2 ]]; then
    echo "validate: delegation telemetry unavailable; coverage unknown" >&2
    exit 2
  fi
  [[ "$dstatus" == 0 ]] || { err "delegation-check failed"; finish; }
  children="$(sed -n 's/.* children=\([0-9]*\).*/\1/p' <<< "$header")"
  depth1="$(sed -n 's/.* depth1=\([0-9]*\).*/\1/p' <<< "$header")"
  effort="$(sed -n 's/.* effort=\([^ ]*\).*/\1/p' <<< "$header")"
  expected="$(jq '.coverage | .finders + .verifier_batches + .dedicated_verifiers' "$out")"
  [[ "$children" == "$depth1" ]] || err "nested delegation ($children children, $depth1 direct)"
  [[ "$children" == "$expected" ]] || err "telemetry shows $children children, coverage claims $expected"
  [[ "$effort" == "$level" ]] || err "child effort $effort, expected $level"
else
  check '(.unchecked_candidates | length) == 0' "verification rounds must not report unchecked candidates"
  prior_files=()
  for ((k = 1; k < n; k++)); do prior_files+=("$run/round-$k.json"); done
  prior="$(jq -s '[to_entries[] | .key as $i | .value.findings[]? | "R\($i + 1)-\(.id)"]' "${prior_files[@]}")"
  jq -e --argjson prior "$prior" 'all(.findings[]; .repeat_of == "" or (.repeat_of as $r | $prior | index($r)))' "$out" > /dev/null \
    || err "repeat_of references an unknown prior finding"
fi

finish
