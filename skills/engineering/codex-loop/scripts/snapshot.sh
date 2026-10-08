#!/usr/bin/env bash
set -euo pipefail

# Immutable review input without touching the real index.
#
# A snapshot is the tree a `git add -A && git commit` would record right now: tracked edits,
# deletions, and untracked non-ignored files. It is built in a temporary index seeded from the
# real one (stat cache only), so the user's staging area is never read as intent or modified.
#
# usage: snapshot.sh init  RUN_DIR [BASE_REF]   preflight, pin HEAD/branch/base, take S0,
#                                               write review.diff + untracked.txt
#        snapshot.sh take  RUN_DIR K            take S_K after round K's fixes, write
#                                               fixes-latest-K.diff (S_{K-1}..S_K) and
#                                               fixes-cumulative-K.diff (S0..S_K)
#        snapshot.sh check RUN_DIR              fail if HEAD or branch moved since init
# exit 0 ok; 1 failure (message on stderr); 4 nothing to review (init only)

fail() {
  echo "snapshot: $*" >&2
  exit 1
}

[[ $# -ge 2 ]] || fail "usage: snapshot.sh <init|take|check> RUN_DIR [ARG]"
action="$1"
run_dir="$2"
[[ -d "$run_dir" && -s "$run_dir/repo" ]] || fail "missing run directory or repo state"
run_dir="$(cd "$run_dir" && pwd)"
repo="$(cat "$run_dir/repo")"
export GIT_OPTIONAL_LOCKS=0
git -C "$repo" rev-parse --show-toplevel > /dev/null || fail "not a git repository: $repo"

DIFF_FLAGS=(--no-color --no-ext-diff --no-textconv -M --binary)

current_branch() {
  git -C "$repo" symbolic-ref -q HEAD || echo DETACHED
}

# Prints the tree id of the working tree as a commit would record it.
take_tree() {
  local index real_index
  index="$(mktemp "$run_dir/index.XXXXXX")"
  real_index="$(git -C "$repo" rev-parse --path-format=absolute --git-path index)"
  (
    export GIT_INDEX_FILE="$index"
    # Seeding from the real index keeps its stat cache and index-only intent (`git rm --cached`).
    if [[ -f "$real_index" ]]; then
      cp "$real_index" "$index"
    else
      rm -f "$index"
      git -C "$repo" read-tree HEAD
    fi
    git -C "$repo" add -A
    git -C "$repo" write-tree
  ) || { rm -f "$index"; fail "could not build snapshot tree"; }
  rm -f "$index"
}

case "$action" in
  init)
    base_ref="${3:-HEAD}"
    [[ ! -e "$run_dir/pins" ]] || fail "already initialized; refusing to reset pins"
    git -C "$repo" rev-parse --verify -q 'HEAD^{commit}' > /dev/null || fail "unborn HEAD; commit first"
    [[ -z "$(git -C "$repo" diff --name-only --diff-filter=U)" ]] || fail "unmerged paths; resolve conflicts first"
    [[ -z "$(git -C "$repo" submodule status 2> /dev/null)" ]] || fail "submodules are not supported"
    base="$(git -C "$repo" rev-parse --verify -q "${base_ref}^{commit}")" || fail "cannot resolve base: $base_ref"
    head="$(git -C "$repo" rev-parse HEAD)"
    git -C "$repo" merge-base --is-ancestor "$base" "$head" || fail "base $base_ref is not an ancestor of HEAD"
    s0="$(take_tree)"
    git -C "$repo" diff "${DIFF_FLAGS[@]}" "$base" "$s0" > "$run_dir/review.diff"
    [[ -s "$run_dir/review.diff" ]] || { rm -f "$run_dir/review.diff"; echo "snapshot: nothing to review against $base_ref" >&2; exit 4; }
    git -C "$repo" ls-files --others --exclude-standard > "$run_dir/untracked.txt"
    {
      printf 'head=%s\n' "$head"
      printf 'branch=%s\n' "$(current_branch)"
      printf 'base=%s\n' "$base"
    } > "$run_dir/pins"
    printf '%s\n' "$s0" > "$run_dir/snap-0"
    echo "snapshot: base=$base S0=$s0 files=$(git -C "$repo" diff --name-only "$base" "$s0" | wc -l | tr -d ' ') untracked=$(wc -l < "$run_dir/untracked.txt" | tr -d ' ')"
    ;;

  take)
    k="${3:-}"
    [[ "$k" =~ ^[1-9][0-9]*$ ]] || fail "take needs a positive round number"
    [[ -s "$run_dir/snap-$((k - 1))" ]] || fail "missing previous snapshot snap-$((k - 1))"
    [[ ! -e "$run_dir/snap-$k" ]] || fail "snap-$k already exists; refusing to overwrite"
    sk="$(take_tree)"
    printf '%s\n' "$sk" > "$run_dir/snap-$k"
    git -C "$repo" diff "${DIFF_FLAGS[@]}" "$(cat "$run_dir/snap-$((k - 1))")" "$sk" > "$run_dir/fixes-latest-$k.diff"
    git -C "$repo" diff "${DIFF_FLAGS[@]}" "$(cat "$run_dir/snap-0")" "$sk" > "$run_dir/fixes-cumulative-$k.diff"
    echo "snapshot: S$k=$sk latest=$(wc -l < "$run_dir/fixes-latest-$k.diff" | tr -d ' ') lines cumulative=$(wc -l < "$run_dir/fixes-cumulative-$k.diff" | tr -d ' ') lines"
    ;;

  check)
    [[ -s "$run_dir/pins" ]] || fail "missing pins; do not recreate them during a run"
    expected_head="$(sed -n 's/^head=//p' "$run_dir/pins")"
    expected_branch="$(sed -n 's/^branch=//p' "$run_dir/pins")"
    actual_head="$(git -C "$repo" rev-parse HEAD)"
    actual_branch="$(current_branch)"
    if [[ "$expected_head" == "$actual_head" && "$expected_branch" == "$actual_branch" ]]; then
      echo "snapshot: pins unchanged"
      exit 0
    fi
    echo "snapshot: HEAD or branch moved (expected $expected_branch@$expected_head, found $actual_branch@$actual_head); stop" >&2
    exit 1
    ;;

  *)
    fail "unknown action: $action"
    ;;
esac
