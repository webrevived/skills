#!/usr/bin/env bash
set -euo pipefail

scripts="$(cd "$(dirname "$0")" && pwd)"
scratch="$(cd "$(mktemp -d "${TMPDIR:-/tmp}/codex-loop-review-test.XXXXXX")" && pwd)"
trap 'rm -rf -- "$scratch"' EXIT

fail() {
  echo "test-review: $*" >&2
  exit 1
}

# Fake codex: records its args and stdin, sleeps, writes the -o file.
mkdir "$scratch/bin"
cat > "$scratch/bin/codex" <<'EOF'
#!/usr/bin/env bash
out=""
while [[ $# -gt 0 ]]; do [[ "$1" == -o ]] && { out="$2"; shift; }; shift; done
cat > "${out%.json}.prompt-seen"
sleep "${FAKE_CODEX_SLEEP:-1}"
printf '{"verdict":"clean"}\n' > "$out"
exit "${FAKE_CODEX_EXIT:-0}"
EOF
chmod +x "$scratch/bin/codex"
export PATH="$scratch/bin:$PATH"

repo="$scratch/repo"
mkdir "$repo"
git -C "$repo" init -q
git -C "$repo" config user.email t@example.com
git -C "$repo" config user.name t
echo a > "$repo/a.txt"; git -C "$repo" add -A; git -C "$repo" commit -qm init
echo b >> "$repo/a.txt"

run="$scratch/run"
mkdir "$run"
printf '%s\n' "$repo" > "$run/repo"
printf 'gpt-test\n' > "$run/model"
printf 'medium\n' > "$run/review-level"
printf 'Look at auth.\n' > "$run/focus.md"
bash "$scripts/round-budget.sh" init "$run" 2
bash "$scripts/snapshot.sh" init "$run" > /dev/null

# Round 1: initial protocol + review input + focus; wait blocks until done.
[[ "$(bash "$scripts/review.sh" "$run")" == "review: round 1 launched" ]] || fail "launch not reported"
[[ "$(bash "$scripts/wait.sh" "$run" 30)" == *"codex exit=0"* ]] || fail "wait did not report completion"
seen="$run/round-1.prompt-seen"
grep -q '^## Review level' "$seen" && grep -q '^medium$' "$seen" || fail "level missing from prompt"
grep -q "Diff file: $run/review.diff" "$seen" || fail "diff path missing from round-1 prompt"
grep -q 'Look at auth.' "$seen" || fail "focus missing from prompt"

# Retry archives the previous attempt.
# Archiving happens before review.sh returns, so wait can never see the stale exit file.
FAKE_CODEX_SLEEP=2 FAKE_CODEX_EXIT=1 bash "$scripts/review.sh" "$run" > /dev/null
[[ -e "$run/round-1-attempt-1.json" && -e "$run/round-1-attempt-1.exit" ]] || fail "previous attempt not archived"
[[ ! -e "$run/round-1.exit" ]] || fail "stale exit file visible after relaunch"
bash "$scripts/wait.sh" "$run" 30 > /dev/null || true
[[ "$(cat "$run/round-1.exit")" == 1 ]] || fail "exit status not recorded"

# Round 2: verification prompt points at fix diffs.
echo fix >> "$repo/a.txt"
bash "$scripts/snapshot.sh" take "$run" 1 > /dev/null
bash "$scripts/round-budget.sh" advance "$run"
set +e; bash "$scripts/review.sh" "$run" 2> /dev/null; status=$?; set -e
[[ "$status" == 1 ]] || fail "round 2 without dispositions should refuse to launch"
printf '{"round":1,"dispositions":[],"questions":[],"checks":[]}\n' > "$run/dispositions-1.json"
bash "$scripts/review.sh" "$run" > /dev/null
bash "$scripts/wait.sh" "$run" 30 > /dev/null
seen="$run/round-2.prompt-seen"
grep -q "Latest fixes (round 1): $run/fixes-latest-1.diff" "$seen" || fail "latest fixes missing"
grep -q "Cumulative fixes since S0: $run/fixes-cumulative-1.diff" "$seen" || fail "cumulative fixes missing"

# Budget exhausted: nothing launched.
bash "$scripts/round-budget.sh" advance "$run"
set +e; bash "$scripts/review.sh" "$run" 2> /dev/null; status=$?; set -e
[[ "$status" == 3 ]] || fail "exhausted budget should exit 3, got $status"
[[ ! -e "$run/round-3.log" ]] || fail "review launched past budget"

# wait reports still-running with exit 75.
bash "$scripts/round-budget.sh" extend "$run" 1
bash "$scripts/snapshot.sh" take "$run" 2 > /dev/null
cp "$run/dispositions-1.json" "$run/dispositions-2.json"
FAKE_CODEX_SLEEP=4 bash "$scripts/review.sh" "$run" > /dev/null
set +e; bash "$scripts/wait.sh" "$run" 0 > /dev/null; status=$?; set -e
[[ "$status" == 75 ]] || fail "wait should exit 75 while running, got $status"
bash "$scripts/wait.sh" "$run" 30 > /dev/null || fail "detached runner did not finish"

echo "test-review: ok"
