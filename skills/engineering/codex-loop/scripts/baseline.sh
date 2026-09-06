#!/usr/bin/env bash
set -euo pipefail

fail() {
  echo "baseline: $*" >&2
  exit 1
}

[[ $# == 2 && ( "$1" == init || "$1" == check ) ]] ||
  fail "usage: baseline.sh <init|check> RUN_DIR"

action="$1"
run_dir="$2"
[[ -d "$run_dir" && -s "$run_dir/repo" ]] || fail "missing run directory or repo state"
repo="$(cat "$run_dir/repo")"
baseline="$run_dir/baseline"
export GIT_OPTIONAL_LOCKS=0
git -C "$repo" rev-parse --show-toplevel > /dev/null

capture() {
  local destination="$1"
  local head_ref status

  if git -C "$repo" rev-parse --verify HEAD > "$destination/head" 2>/dev/null; then
    git -C "$repo" cat-file -e 'HEAD^{commit}'
  else
    head_ref="$(git -C "$repo" symbolic-ref -q HEAD)" || fail "cannot resolve HEAD"
    if git -C "$repo" show-ref --verify --quiet "$head_ref"; then
      fail "HEAD exists but cannot be resolved"
    else
      status=$?
      [[ "$status" == 1 ]] || fail "cannot inspect HEAD reference"
    fi
    printf 'UNBORN:%s\n' "$head_ref" > "$destination/head"
  fi

  # Raw staged metadata includes intent-to-add semantics without rendering file contents.
  git -C "$repo" diff --cached --raw --no-abbrev --no-renames --no-color \
    --no-ext-diff --no-textconv --ignore-submodules=none --ita-invisible-in-index -z \
    > "$destination/entries"
}

if [[ "$action" == init ]]; then
  mkdir "$baseline" || fail "baseline already exists or cannot be created; refusing to reset it"
  capture "$baseline"
  touch "$baseline/ready"
  echo "baseline: saved HEAD and staged entries"
  exit 0
fi

[[ -f "$baseline/ready" && -s "$baseline/head" && -f "$baseline/entries" ]] ||
  fail "missing or incomplete baseline; do not recreate it during a run"

snapshot="$(mktemp -d "$run_dir/baseline-check.XXXXXX")"
trap 'rm -rf -- "$snapshot"' EXIT
capture "$snapshot"

if cmp -s "$baseline/head" "$snapshot/head" && cmp -s "$baseline/entries" "$snapshot/entries"; then
  echo "baseline: unchanged"
  exit 0
fi

echo "baseline: HEAD or staged entries changed; stop without repairing the index" >&2
echo "baseline: expected state is in $baseline" >&2
git -C "$repo" status --short >&2
exit 1
