#!/usr/bin/env bash
set -euo pipefail

# Computes the run's machine-readable outcome from valid rounds and dispositions, writes
# outcome.json, and prints a compact summary. Callers (build-plan) gate on `.outcome`.
#
# usage: outcome.sh RUN_DIR [--stop REASON]
#   --stop REASON  record why the loop stopped early (stalemate, thrash, budget, review-failed,
#                  telemetry-unknown, baseline-drift); stalemate/thrash escalate, others are open.
#
# clean    — last valid review is clean, or its findings were all closed without applied fixes,
#            and initial coverage is complete
# open     — applied fixes await verification, initial candidates are unchecked, findings lack
#            dispositions, no valid review exists, or the loop stopped early
# escalate — an unresolved question or a stalemate/thrash needs a human decision

run="${1:?usage: outcome.sh RUN_DIR [--stop REASON]}"
stop=""
[[ "${2:-}" == --stop ]] && stop="${3:?--stop needs a reason}"

last=0
for f in "$run"/round-*.valid; do
  [[ -e "$f" ]] || continue
  k="${f##*/round-}"; k="${k%.valid}"
  [[ "$k" =~ ^[0-9]+$ ]] || continue   # skip archived round-N-attempt-K.valid
  (( k > last )) && last="$k"
done

empty='{"findings":[],"unchecked_candidates":[]}'
r1="$empty"; [[ -e "$run/round-1.valid" ]] && r1="$(cat "$run/round-1.json")"
rl="$empty"; (( last > 0 )) && rl="$(cat "$run/round-$last.json")"
dl='{"dispositions":[],"questions":[]}'
(( last > 0 )) && [[ -s "$run/dispositions-$last.json" ]] && dl="$(cat "$run/dispositions-$last.json")"
all_dispositions='[]'
if compgen -G "$run/dispositions-*.json" > /dev/null; then
  all_dispositions="$(jq -s '[.[].dispositions[]?]' "$run"/dispositions-*.json)"
fi

jq -n \
  --argjson last "$last" --arg stop "$stop" --arg level "$(cat "$run/review-level")" \
  --argjson r1 "$r1" --argjson rl "$rl" --argjson dl "$dl" --argjson all "$all_dispositions" '
  ($dl.dispositions | map({key: .id, value: .disposition}) | from_entries) as $disp
  | ($rl.findings | map(select(($disp[.id] // "none") | IN("accepted", "modified", "none")))
      | map({id: "R\($last)-\(.id)", title, file, line, state: (if $disp[.id] then "fix unverified" else "no disposition" end)})) as $pending
  | ($r1.unchecked_candidates | map({id, file, line, summary, reason})) as $unchecked
  | ($dl.questions // []) as $questions
  | ($all | map(select(.disposition == "separate-follow-up"))) as $follow
  | {
      outcome: (
        if ($questions | length) > 0 or ($stop | IN("stalemate", "thrash")) then "escalate"
        elif $last == 0 or $stop != "" or ($pending | length) > 0 or ($unchecked | length) > 0 then "open"
        else "clean" end),
      level: $level, rounds: $last, stop_reason: $stop,
      pending: $pending, unchecked: $unchecked, questions: $questions, follow_ups: $follow
    }' > "$run/outcome.json"

jq -r '"outcome=\(.outcome) level=\(.level) rounds=\(.rounds)\(if .stop_reason != "" then " stop=\(.stop_reason)" else "" end) pending=\(.pending | length) unchecked=\(.unchecked | length) questions=\(.questions | length) follow_ups=\(.follow_ups | length)"' "$run/outcome.json"
