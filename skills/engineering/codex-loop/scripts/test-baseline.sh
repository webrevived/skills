#!/usr/bin/env bash
set -euo pipefail

helper="$(cd "$(dirname "$0")" && pwd)/baseline.sh"
scratch="$(mktemp -d "${TMPDIR:-/tmp}/codex-loop-baseline-test.XXXXXX")"
trap 'rm -rf -- "$scratch"' EXIT
repo="$scratch/repo with spaces"
mkdir "$repo"

# Isolate fixtures from user hooks, signing, templates, and global/system Git settings.
export GIT_CONFIG_NOSYSTEM=1
export GIT_CONFIG_GLOBAL=/dev/null
export GIT_TEMPLATE_DIR="$scratch/empty-template"
mkdir "$GIT_TEMPLATE_DIR"

fixture_git() {
  git -C "$repo" -c user.name=Test -c user.email=test@example.invalid \
    -c commit.gpgSign=false -c core.hooksPath=/dev/null "$@"
}

expect_failure() {
  if "$@" > "$scratch/failure.log" 2>&1; then
    echo "test-baseline: expected failure: $*" >&2
    exit 1
  fi
}

new_baseline() {
  run_dir="$(mktemp -d "$scratch/run.XXXXXX")"
  printf '%s\n' "$repo" > "$run_dir/repo"
  bash "$helper" init "$run_dir" > /dev/null
}

check_unchanged() {
  bash "$helper" check "$run_dir" > /dev/null
}

check_changed() {
  expect_failure bash "$helper" check "$run_dir"
}

fixture_git init -q
printf 'base\n' > "$repo/text file"
printf '\0\1\2' > "$repo/binary"
printf 'odd path\n' > "$repo/line
break"
fixture_git add .

# A first commit changes HEAD even when staged entries remain identical.
new_baseline
check_unchanged
expect_failure bash "$helper" init "$run_dir"
fixture_git commit -qm baseline
check_changed
new_baseline

# Cache refreshes, Git diff configuration, and working-tree fixes are not staging changes.
touch -t 202001010000 "$repo/text file"
fixture_git update-index --refresh
fixture_git config diff.noprefix true
fixture_git config diff.renames false
fixture_git config core.abbrev 5
fixture_git config diff.external false
check_unchanged
printf 'unstaged fix\n' > "$repo/text file"
printf 'new unstaged fix\n' > "$repo/new file"
check_unchanged
fixture_git add 'text file'
check_changed
new_baseline

# Binary content, modes, additions, renames, removals, and unstaging all matter.
printf '\0\1\3' > "$repo/binary"
fixture_git add binary
check_changed
new_baseline
fixture_git update-index --chmod=+x binary
check_changed
new_baseline
fixture_git add 'new file'
check_changed
new_baseline
fixture_git mv 'new file' renamed
check_changed
new_baseline
fixture_git rm -q -f renamed
check_changed
new_baseline
fixture_git reset -q HEAD -- 'text file'
check_changed
new_baseline

# Intent-to-add and a staged empty file share ls-files entries but have different staged diffs.
touch "$repo/empty"
fixture_git add empty
new_baseline
fixture_git reset -q -N HEAD -- empty
check_changed
fixture_git add empty
new_baseline

# HEAD changes must be detected independently of index content.
fixture_git commit -qm 'commit staged fixture changes'
check_changed
new_baseline
fixture_git commit --allow-empty -qm 'advance only HEAD'
check_changed

# Linked worktrees and invocation from an unrelated directory use the saved repository.
fixture_git worktree add -q -b fixture-linked "$scratch/linked worktree"
repo="$scratch/linked worktree"
new_baseline
(cd /; bash "$helper" check "$run_dir" > /dev/null)
rm "$run_dir/baseline/head"
check_changed
new_baseline
rm "$run_dir/baseline/ready"
check_changed
expect_failure bash "$helper" init "$run_dir"

# Missing repositories and broken refs must not be accepted as an unborn branch.
printf '%s\n' "$scratch/nonexistent" > "$run_dir/repo"
check_changed
repo="$scratch/repo with spaces"
new_baseline
branch_ref="$(fixture_git symbolic-ref HEAD)"
printf 'invalid object id\n' > "$repo/.git/$branch_ref"
check_changed
broken_run="$(mktemp -d "$scratch/broken.XXXXXX")"
printf '%s\n' "$repo" > "$broken_run/repo"
expect_failure bash "$helper" init "$broken_run"
[[ ! -e "$broken_run/baseline/ready" ]]

echo "test-baseline: all checks passed"
