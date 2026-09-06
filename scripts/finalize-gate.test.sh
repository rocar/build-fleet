#!/usr/bin/env bash
# Tests for scripts/finalize-gate.sh (v0.9 rubric-only gate). Builds a fixture
# workspace per case, asserts the BUILD_FLEET_FINALIZE_GATE line + exit code.
# Run: bash scripts/finalize-gate.test.sh   (exit 0 = all pass)
set -uo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GATE="$DIR/finalize-gate.sh"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
pass=0; fail=0

# new_proj <name> <cycle> → fixture with feature 'feat' at CYCLE <cycle>, roster default
new_proj() {
  local p="$work/$1"
  mkdir -p "$p/.sdd/feat"
  printf 'PHASE: REVIEW\nCYCLE: %s\nREVIEW_ROLES: architect, qa, coder\n' "$2" > "$p/.sdd/feat/PROGRESS.md"
  printf '# Architecture Decisions — feat\n\n## ADR-4: accept x\n\n- **Status:** accepted\n' > "$p/.sdd/feat/DECISIONS.md"
  printf '# Review Log — feat\n\nAppend-only.\n\n' > "$p/.sdd/feat/REVIEW.md"
  printf '%s' "$p"
}
# block <proj> <cycle> <role> <body-lines…>
block() { local p="$1" c="$2" r="$3"; shift 3; { printf '## Cycle %s — %s — 2026-09-03T00:00:00Z\n' "$c" "$r"; for l in "$@"; do printf '%s\n' "$l"; done; printf 'status: concerns-raised\n\n'; } >> "$p/.sdd/feat/REVIEW.md"; }
# run <proj> → sets rc + out
run() { out=$( cd "$1" && CLAUDE_PROJECT_DIR="$1" bash "$GATE" feat 2>/dev/null ); rc=$?; }
assert() { local name="$1" cond="$2"; if eval "$cond"; then pass=$((pass+1)); printf 'ok   %-44s\n' "$name"; else fail=$((fail+1)); printf 'FAIL %-44s (%s) out=%s\n' "$name" "$cond" "${out:-}"; fi; }

# --- pass: all roles present, blocker-free, majors adr'd (ADR exists) or refuted ---
p=$(new_proj ok 2)
block "$p" 2 architect '- [major] (architect-c1-2) accepted' '  disposition: adr ADR-4' '- [minor] (architect-c2-1) nit'
block "$p" 2 qa '- [major] (qa-c1-1) refuted' '  refuted-by: coder — reason: long enough reason here for sure (cites spec.md § A)'
block "$p" 2 coder
run "$p"
assert "pass-rc0" "[ $rc -eq 0 ]"
assert "pass-line" "printf '%s' \"\$out\" | grep -q '\"pass\":true,\"reasons\":\\[\\]'"

# --- refuse: a fix-dispositioned major ---
p=$(new_proj fix 2); block "$p" 2 architect '- [major] (architect-c2-1) open' '  disposition: fix'; block "$p" 2 qa; block "$p" 2 coder
run "$p"
assert "fix-major-refuses" "[ $rc -eq 2 ]"
assert "fix-major-reason" "printf '%s' \"\$out\" | grep -q 'majors-open'"
assert "fix-major-id-listed" "printf '%s' \"\$out\" | grep -q '\"open_majors\":\\[\"architect-c2-1\"\\]'"

# --- refuse: a major with no disposition line at all (legacy block) is open ---
p=$(new_proj legacy 1); block "$p" 1 architect '- [major] legacy text without id or disposition'; block "$p" 1 qa; block "$p" 1 coder
run "$p"
assert "undispositioned-major-refuses" "[ $rc -eq 2 ] && printf '%s' \"\$out\" | grep -q majors-open"

# --- refuse: adr disposition citing an ADR that does not exist ---
p=$(new_proj noadr 2); block "$p" 2 architect '- [major] (architect-c2-1) x' '  disposition: adr ADR-9'; block "$p" 2 qa; block "$p" 2 coder
run "$p"
assert "missing-adr-refuses" "[ $rc -eq 2 ] && printf '%s' \"\$out\" | grep -q majors-without-adr"
# zero-padded citation of an existing ADR passes
p=$(new_proj pad 2); block "$p" 2 architect '- [major] (architect-c2-1) x' '  disposition: adr ADR-004'; block "$p" 2 qa; block "$p" 2 coder
run "$p"
assert "zero-padded-adr-passes" "[ $rc -eq 0 ]"

# --- refuse: open blocker ---
p=$(new_proj blk 2); block "$p" 2 architect '- [blocker] (architect-c2-1) b'; block "$p" 2 qa; block "$p" 2 coder
run "$p"
assert "blocker-refuses" "[ $rc -eq 2 ] && printf '%s' \"\$out\" | grep -q open-blockers"

# --- pass: a refuted blocker is closed (agrees with review.js finalize_ready) ---
p=$(new_proj refblk 2)
block "$p" 2 architect '- [blocker] (architect-c2-1) refuted' '  refuted-by: coder — reason: long enough reason here for sure (cites spec.md § A)'
block "$p" 2 qa; block "$p" 2 coder
run "$p"
assert "refuted-blocker-passes" "[ $rc -eq 0 ] && printf '%s' \"\$out\" | grep -q '\"open_blockers\":\\[\\]'"

# --- C1: a legacy hand-written multi-line finding text (second text line indented by
# two spaces, same as a real continuation) does not stop the gate from finding the
# ACTUAL continuation (refuted-by / disposition) further down the indented run ---
p=$(new_proj multiline 2)
block "$p" 2 architect '- [blocker] (architect-c2-1) first line of blocker text' '  second line of blocker text, hand-wrapped' '  refuted-by: coder — reason: long enough reason here for sure (cites spec.md § A)'
block "$p" 2 qa '- [major] (qa-c2-1) first line of major text' '  second line of major text, hand-wrapped' '  disposition: adr ADR-4'
block "$p" 2 coder
run "$p"
assert "multiline-legacy-text-passes" "[ $rc -eq 0 ]"
assert "multiline-legacy-text-open-blockers-empty" "printf '%s' \"\$out\" | grep -q '\"open_blockers\":\\[\\]'"
assert "multiline-legacy-text-open-majors-empty" "printf '%s' \"\$out\" | grep -q '\"open_majors\":\\[\\]'"

# --- refuse: a roster role has no current-cycle block (stale cycle only) ---
p=$(new_proj miss 2); block "$p" 1 architect; block "$p" 2 qa; block "$p" 2 coder
run "$p"
assert "missing-role-refuses" "[ $rc -eq 2 ] && printf '%s' \"\$out\" | grep -q missing-architect"

# --- status lines are ignored: concerns-raised with everything closed still passes ---
p=$(new_proj status 2); block "$p" 2 architect; block "$p" 2 qa; block "$p" 2 coder
run "$p"
assert "status-line-not-evaluated" "[ $rc -eq 0 ]"

# --- last block per role wins (a later same-cycle block supersedes) ---
p=$(new_proj last 2); block "$p" 2 architect '- [blocker] (architect-c2-1) early'; block "$p" 2 qa; block "$p" 2 coder; block "$p" 2 architect
run "$p"
assert "last-block-per-role-wins" "[ $rc -eq 0 ]"

# --- roster override flag ---
p=$(new_proj roster 2); block "$p" 2 architect; block "$p" 2 qa
out=$( cd "$p" && CLAUDE_PROJECT_DIR="$p" bash "$GATE" feat --roster architect,qa 2>/dev/null ); rc=$?
assert "roster-flag-two-roles-pass" "[ $rc -eq 0 ]"

# --- bad input: missing PROGRESS → exit 1 ---
p="$work/noprog"; mkdir -p "$p/.sdd/feat"
out=$( cd "$p" && CLAUDE_PROJECT_DIR="$p" bash "$GATE" feat 2>/dev/null ); rc=$?
assert "no-progress-exit-1" "[ $rc -eq 1 ]"

# --- bad input: slug shifted away, first arg looks like a flag → exit 1 ---
out=$( bash "$GATE" --roster architect,qa 2>/dev/null ); rc=$?
assert "dash-slug-exit-1" "[ $rc -eq 1 ]"

echo "-----"; echo "passed=$pass failed=$fail"; [ "$fail" -eq 0 ]
