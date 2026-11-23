#!/usr/bin/env bash
set -euo pipefail

# Checks the fixer's dispositions for the current round against that round's findings:
# every finding ID gets exactly one allowed disposition or one question, and nothing else.
#
# usage: check-dispositions.sh RUN_DIR
# exit 0: valid; 1: invalid (reasons on stderr)

run="${1:?usage: check-dispositions.sh RUN_DIR}"
n="$(bash "$(dirname "$0")/round-budget.sh" current "$run")"
findings="$run/round-$n.json"
out="$run/dispositions-$n.json"

[[ -s "$findings" ]] || { echo "check-dispositions: missing $findings" >&2; exit 1; }
jq -se 'length == 1 and (.[0].dispositions | type == "array") and ((.[0].questions // []) | type == "array")
  and all(.[0].dispositions[], (.[0].questions // [])[]; type == "object" and (.id | type == "string"))' \
  "$out" > /dev/null 2>&1 \
  || { echo "check-dispositions: $out must be one {dispositions: [], questions: []} object whose entries each have a string id" >&2; exit 1; }

errors="$(jq -r --slurpfile f "$findings" '
  ["accepted", "modified", "rejected", "outside-review", "separate-follow-up", "user-deferred"] as $allowed
  | ([$f[0].findings[].id]) as $want
  | ([.dispositions[].id] + [(.questions // [])[].id]) as $got
  | (.dispositions[] | select(.disposition | IN($allowed[]) | not)
      | "\(.id): disposition \(.disposition | tojson) is not one of \($allowed | join(", "))"),
    ($want - $got | .[] | "\(.): no disposition or question"),
    ($got - $want | unique | .[] | "\(.): not a finding of round '"$n"'"),
    ($got | group_by(.) | map(select(length > 1)[0]) | .[] | "\(.): more than one disposition or question")
' "$out")"

if [[ -n "$errors" ]]; then
  echo "check-dispositions: round $n invalid:" >&2
  sed 's/^/  - /' <<< "$errors" >&2
  exit 1
fi
echo "check-dispositions: round $n valid"
