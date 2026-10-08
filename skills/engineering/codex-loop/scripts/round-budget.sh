#!/usr/bin/env bash
set -euo pipefail

usage() {
  echo "usage: round-budget.sh <init|current|guard|advance|extend|show> RUN_DIR [VALUE]" >&2
}

fail() {
  echo "round-budget: $*" >&2
  exit 1
}

is_positive_integer() {
  [[ "$1" =~ ^[1-9][0-9]*$ ]]
}

read_state_value() {
  local path="$1"
  local label="$2"
  local value

  [[ -f "$path" ]] || fail "missing $label state: $path"
  value="$(<"$path")"
  is_positive_integer "$value" || fail "invalid $label state: $value"
  printf '%s\n' "$value"
}

write_state_value() {
  local path="$1"
  local value="$2"
  local temporary_path="${path}.tmp.$$"

  printf '%s\n' "$value" > "$temporary_path"
  mv "$temporary_path" "$path"
}

command_name="${1:-}"
[[ -n "$command_name" ]] || {
  usage
  exit 64
}
shift

run_dir="${1:-}"
[[ -n "$run_dir" ]] || {
  usage
  exit 64
}
shift

round_path="$run_dir/round-number"
budget_path="$run_dir/round-budget"

case "$command_name" in
  init)
    budget="${1:-3}"
    [[ -d "$run_dir" ]] || fail "run directory does not exist: $run_dir"
    is_positive_integer "$budget" || fail "budget must be a positive integer"
    [[ ! -e "$round_path" && ! -e "$budget_path" ]] ||
      fail "round state already exists; refusing to reset it"
    write_state_value "$round_path" 1
    write_state_value "$budget_path" "$budget"
    ;;

  current)
    read_state_value "$round_path" "round"
    ;;

  guard)
    current_round="$(read_state_value "$round_path" "round")"
    current_budget="$(read_state_value "$budget_path" "budget")"

    if (( current_round > current_budget )); then
      echo "round-budget: round $current_round requires explicit approval; automatic budget is $current_budget" >&2
      exit 3
    fi

    echo "round-budget: round $current_round of $current_budget authorized"
    ;;

  advance)
    current_round="$(read_state_value "$round_path" "round")"
    write_state_value "$round_path" "$((current_round + 1))"
    ;;

  extend)
    extension="${1:-1}"
    is_positive_integer "$extension" || fail "extension must be a positive integer"
    current_budget="$(read_state_value "$budget_path" "budget")"
    write_state_value "$budget_path" "$((current_budget + extension))"
    ;;

  show)
    current_round="$(read_state_value "$round_path" "round")"
    current_budget="$(read_state_value "$budget_path" "budget")"
    printf 'round=%s budget=%s\n' "$current_round" "$current_budget"
    ;;

  *)
    usage
    exit 64
    ;;
esac
