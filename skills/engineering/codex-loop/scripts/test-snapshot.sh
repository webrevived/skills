#!/usr/bin/env bash
set -euo pipefail

helper="$(cd "$(dirname "$0")" && pwd)/snapshot.sh"
scratch="$(mktemp -d "${TMPDIR:-/tmp}/codex-loop-snapshot-test.XXXXXX")"
trap 'rm -rf -- "$scratch"' EXIT

fail() {
  echo "test-snapshot: $*" >&2
  exit 1
}

new_run() {
  local run
  run="$(mktemp -d "$scratch/run.XXXXXX")"
  printf '%s\n' "$repo" > "$run/repo"
  printf '%s\n' "$run"
}

repo="$scratch/repo with spaces"
mkdir "$repo"
git -C "$repo" init -q
git -C "$repo" config user.email t@example.com
git -C "$repo" config user.name t
printf 'dist/\n.env\n' > "$repo/.gitignore"
echo a > "$repo/a.txt"
echo keep > "$repo/old.txt"
git -C "$repo" add -A
git -C "$repo" commit -qm init
first="$(git -C "$repo" rev-parse HEAD)"

# Clean tree: nothing to review.
run="$(new_run)"
set +e; bash "$helper" init "$run" > /dev/null 2>&1; status=$?; set -e
[[ "$status" == 4 ]] || fail "clean tree should exit 4, got $status"

# Mixed state: partial staging, untracked, ignored, rename, binary.
echo a2 >> "$repo/a.txt"
git -C "$repo" add a.txt
echo a3 >> "$repo/a.txt"
echo new > "$repo/new.txt"
mkdir "$repo/dist"; echo gen > "$repo/dist/x.js"
echo SECRET > "$repo/.env"
git -C "$repo" mv old.txt renamed.txt
printf '\x00\x01\x02' > "$repo/bin.dat"
index_before="$(git -C "$repo" diff --cached --raw)"

run="$(new_run)"
bash "$helper" init "$run" > /dev/null
[[ "$(git -C "$repo" diff --cached --raw)" == "$index_before" ]] || fail "real index changed"
files="$(git -C "$repo" ls-tree -r --name-only "$(cat "$run/snap-0")" | sort | tr '\n' ' ')"
[[ "$files" == ".gitignore a.txt bin.dat new.txt renamed.txt " ]] || fail "unexpected S0 files: $files"
grep -q '^+a3$' "$run/review.diff" || fail "unstaged edit missing from review.diff"
grep -q 'rename from old.txt' "$run/review.diff" || fail "rename not detected"
grep -q 'GIT binary patch' "$run/review.diff" || fail "binary not included"
! grep -q SECRET "$run/review.diff" || fail "ignored file leaked into review.diff"
[[ "$(sort "$run/untracked.txt" | tr '\n' ' ')" == "bin.dat new.txt " ]] || fail "untracked list wrong"

# Fix round: latest and cumulative views.
echo fix >> "$repo/new.txt"
echo extra > "$repo/fix2.txt"
bash "$helper" take "$run" 1 > /dev/null
grep -q '^+fix$' "$run/fixes-latest-1.diff" || fail "fix missing from latest"
! grep -q '^+a3$' "$run/fixes-latest-1.diff" || fail "reviewed input leaked into latest fixes"
echo fix2 >> "$repo/new.txt"
bash "$helper" take "$run" 2 > /dev/null
! grep -q '^+fix$' "$run/fixes-latest-2.diff" || fail "round-1 fix leaked into round-2 latest"
grep -q '^+fix$' "$run/fixes-cumulative-2.diff" || fail "cumulative lost round-1 fix"
set +e; bash "$helper" take "$run" 2 > /dev/null 2>&1; status=$?; set -e
[[ "$status" == 1 ]] || fail "overwriting a snapshot should fail"

# Pins.
bash "$helper" check "$run" > /dev/null || fail "check should pass before HEAD moves"
git -C "$repo" add -A
git -C "$repo" commit -qm moved
set +e; bash "$helper" check "$run" > /dev/null 2>&1; status=$?; set -e
[[ "$status" == 1 ]] || fail "check should fail after a commit"

# Committed range via base.
run="$(new_run)"
bash "$helper" init "$run" "$first" > /dev/null
grep -q '^+fix2$' "$run/review.diff" || fail "base range missing committed work"
set +e; bash "$helper" init "$run" "$first" > /dev/null 2>&1; status=$?; set -e
[[ "$status" == 1 ]] || fail "re-init should refuse to reset pins"

echo "test-snapshot: ok"
