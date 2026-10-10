#!/usr/bin/env bash
# Tests for scripts/change-review-gate.sh (rubric-only CHANGE_REVIEW gate). Builds a
# fixture workspace per case, asserts the BUILD_FLEET_CHANGE_REVIEW_GATE line + exit code.
# Run: bash scripts/change-review-gate.test.sh   (exit 0 = all pass)
set -uo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GATE="$DIR/change-review-gate.sh"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
pass=0; fail=0

# new_proj <name> <change_cycle> → fixture with feature 'feat' at CHANGE_CYCLE <n>
new_proj() {
  local p="$work/$1"
  mkdir -p "$p/.sdd/feat"
  printf 'PHASE: CHANGE_REVIEW\nCYCLE: 2\nCHANGE_CYCLE: %s\n' "$2" > "$p/.sdd/feat/PROGRESS.md"
  printf '# Architecture Decisions — feat\n\n## ADR-4: accept x\n\n- **Status:** accepted\n' > "$p/.sdd/feat/DECISIONS.md"
  printf '# Review Log — feat\n\nAppend-only.\n\n' > "$p/.sdd/feat/REVIEW.md"
  printf '%s' "$p"
}
# cblock <proj> <change_cycle> <role> <body-lines…>   (em-dash heading, the scribe/agent default)
cblock() { local p="$1" c="$2" r="$3"; shift 3; { printf '## Change-Cycle %s — %s — 2026-10-12T00:00:00Z\n' "$c" "$r"; for l in "$@"; do printf '%s\n' "$l"; done; printf 'status: concerns-raised\n\n'; } >> "$p/.sdd/feat/REVIEW.md"; }
# dblock <proj> <dash> <change_cycle> <role> <body-lines…>   (explicit dash variant)
dblock() { local p="$1" d="$2" c="$3" r="$4"; shift 4; { printf '## Change-Cycle %s %s %s %s 2026-10-12T00:00:00Z\n' "$c" "$d" "$r" "$d"; for l in "$@"; do printf '%s\n' "$l"; done; printf 'status: approved\n\n'; } >> "$p/.sdd/feat/REVIEW.md"; }
# sblock <proj> <cycle> <role> <body-lines…>   (a SPEC-review block, must never match)
sblock() { local p="$1" c="$2" r="$3"; shift 3; { printf '## Cycle %s — %s — 2026-10-12T00:00:00Z\n' "$c" "$r"; for l in "$@"; do printf '%s\n' "$l"; done; printf 'status: concerns-raised\n\n'; } >> "$p/.sdd/feat/REVIEW.md"; }
run() { out=$( cd "$1" && CLAUDE_PROJECT_DIR="$1" bash "$GATE" feat 2>/dev/null ); rc=$?; }
assert() { local name="$1" cond="$2"; if eval "$cond"; then pass=$((pass+1)); printf 'ok   %-48s\n' "$name"; else fail=$((fail+1)); printf 'FAIL %-48s (%s) out=%s\n' "$name" "$cond" "${out:-}"; fi; }

# --- pass: zero findings in all three roster blocks ---
p=$(new_proj zero 1); cblock "$p" 1 product-owner; cblock "$p" 1 qa; cblock "$p" 1 architect
run "$p"
assert "zero-findings-pass-rc0" "[ $rc -eq 0 ]"
assert "zero-findings-line" "printf '%s' \"\$out\" | grep -q '^BUILD_FLEET_CHANGE_REVIEW_GATE: {\"feature\":\"feat\",\"change_cycle\":1,\"pass\":true,\"reasons\":\\[\\]'"

# --- refuse: open blocker ---
p=$(new_proj blk 1); cblock "$p" 1 product-owner '- [blocker] (product-owner-cc1-1) AC-3 not met'; cblock "$p" 1 qa; cblock "$p" 1 architect
run "$p"
assert "blocker-refuses" "[ $rc -eq 2 ] && printf '%s' \"\$out\" | grep -q open-blockers"

# --- refuse: fix major open, id listed ---
p=$(new_proj fix 1); cblock "$p" 1 product-owner; cblock "$p" 1 qa '- [major] (qa-cc1-1) failure path untested' '  disposition: fix'; cblock "$p" 1 architect
run "$p"
assert "fix-major-refuses" "[ $rc -eq 2 ] && printf '%s' \"\$out\" | grep -q majors-open"
assert "fix-major-id-listed" "printf '%s' \"\$out\" | grep -q '\"open_majors\":\\[\"qa-cc1-1\"\\]'"

# --- pass: architect's own major accepted by an existing ADR ---
p=$(new_proj adr 1); cblock "$p" 1 product-owner; cblock "$p" 1 qa; cblock "$p" 1 architect '- [major] (architect-cc1-1) trade-off' '  disposition: adr ADR-4'
run "$p"
assert "adr-major-passes" "[ $rc -eq 0 ]"

# --- refuse: adr disposition citing an ADR that does not exist ---
p=$(new_proj noadr 1); cblock "$p" 1 product-owner; cblock "$p" 1 qa; cblock "$p" 1 architect '- [major] (architect-cc1-1) x' '  disposition: adr ADR-9'
run "$p"
assert "missing-adr-refuses" "[ $rc -eq 2 ] && printf '%s' \"\$out\" | grep -q majors-without-adr"
assert "missing-adr-id-listed" "printf '%s' \"\$out\" | grep -q '\"majors_without_adr\":\\[\"architect-cc1-1\"\\]'"

# --- refuse: a roster role has no current-cycle block ---
p=$(new_proj miss 2); cblock "$p" 1 architect; cblock "$p" 2 product-owner; cblock "$p" 2 qa
run "$p"
assert "missing-role-refuses" "[ $rc -eq 2 ] && printf '%s' \"\$out\" | grep -q missing-architect"

# --- pass: closed-by-id — qa's fix major is re-listed by the architect with an ADR ---
p=$(new_proj closedbyid 1)
cblock "$p" 1 product-owner
cblock "$p" 1 qa '- [major] (qa-cc1-2) retries not covered' '  disposition: fix'
cblock "$p" 1 architect '- [major] (qa-cc1-2) retries not covered: accepted, no retry path by design' '  disposition: adr ADR-4'
run "$p"
assert "closed-by-id-passes" "[ $rc -eq 0 ]"
assert "closed-by-id-open-majors-empty" "printf '%s' \"\$out\" | grep -q '\"open_majors\":\\[\\]'"

# --- pass + demoted: a NEW major at change cycle 2 (id originates at cycle 2) is advisory ---
p=$(new_proj demote 2); cblock "$p" 2 product-owner; cblock "$p" 2 qa '- [major] (qa-cc2-1) new maintainability nit in the fix' '  disposition: fix'; cblock "$p" 2 architect
run "$p"
assert "new-major-cycle2-passes" "[ $rc -eq 0 ]"
assert "new-major-cycle2-demoted-listed" "printf '%s' \"\$out\" | grep -q '\"demoted\":\\[\"qa-cc2-1\"\\]'"

# --- refuse: a RE-RAISED cycle-1 major at change cycle 2 stays open ---
p=$(new_proj reraise 2); cblock "$p" 2 product-owner; cblock "$p" 2 qa '- [major] (qa-cc1-1) still untested' '  disposition: fix'; cblock "$p" 2 architect
run "$p"
assert "reraised-major-cycle2-refuses" "[ $rc -eq 2 ] && printf '%s' \"\$out\" | grep -q '\"open_majors\":\\[\"qa-cc1-1\"\\]'"

# --- refuse: a NEW blocker at change cycle 2 is never demoted ---
p=$(new_proj blk2 2); cblock "$p" 2 product-owner; cblock "$p" 2 qa '- [blocker] (qa-cc2-1) AC-7 test missing'; cblock "$p" 2 architect
run "$p"
assert "new-blocker-cycle2-refuses" "[ $rc -eq 2 ] && printf '%s' \"\$out\" | grep -q open-blockers"

# --- no demotion at cycle 1 (K == 1 but cycle < 2) ---
p=$(new_proj nodemote1 1); cblock "$p" 1 product-owner; cblock "$p" 1 qa '- [major] (qa-cc1-1) x' '  disposition: fix'; cblock "$p" 1 architect
run "$p"
assert "cycle1-major-not-demoted" "[ $rc -eq 2 ] && printf '%s' \"\$out\" | grep -q '\"demoted\":\\[\\]'"

# --- refuse: legacy block, no ids, undispositioned major is open ---
p=$(new_proj legacy 1); cblock "$p" 1 product-owner; cblock "$p" 1 qa '- [major] legacy text without id or disposition'; cblock "$p" 1 architect
run "$p"
assert "legacy-undispositioned-major-refuses" "[ $rc -eq 2 ] && printf '%s' \"\$out\" | grep -q majors-open"

# --- pass: refuted-by continuation closes a blocker and a major (parity with finalize-gate) ---
p=$(new_proj refuted 1)
cblock "$p" 1 product-owner '- [blocker] (product-owner-cc1-1) refuted' '  refuted-by: architect — reason: AC-3 is satisfied by tests/test_x.py::test_ac3'
cblock "$p" 1 qa '- [major] (qa-cc1-1) refuted' '  refuted-by: architect — reason: covered by tests/test_y.py'
cblock "$p" 1 architect
run "$p"
assert "refuted-by-closes" "[ $rc -eq 0 ]"

# --- heading dash variants: en-dash, hyphen, em-dash all match ---
p=$(new_proj dashes 1); dblock "$p" '–' 1 product-owner; dblock "$p" '-' 1 qa; dblock "$p" '—' 1 architect
run "$p"
assert "dash-variants-match" "[ $rc -eq 0 ]"

# --- a same-numbered SPEC-review block with an open blocker is ignored ---
p=$(new_proj specblock 1); sblock "$p" 1 architect '- [blocker] (architect-c1-1) spec-review blocker, closed history'; cblock "$p" 1 product-owner; cblock "$p" 1 qa; cblock "$p" 1 architect
run "$p"
assert "spec-review-block-ignored" "[ $rc -eq 0 ]"

# --- status lines are ignored: concerns-raised with nothing open passes (covered above); approved with an open blocker still fails ---
p=$(new_proj status 1); dblock "$p" '—' 1 product-owner '- [blocker] (product-owner-cc1-1) approved-but-open'; cblock "$p" 1 qa; cblock "$p" 1 architect
run "$p"
assert "approved-status-not-trusted" "[ $rc -eq 2 ]"

# --- last block per role wins ---
p=$(new_proj last 1); cblock "$p" 1 product-owner; cblock "$p" 1 qa '- [blocker] (qa-cc1-1) early'; cblock "$p" 1 architect; cblock "$p" 1 qa
run "$p"
assert "last-block-per-role-wins" "[ $rc -eq 0 ]"

# --- roster override flag ---
p=$(new_proj roster 1); cblock "$p" 1 architect; cblock "$p" 1 qa
out=$( cd "$p" && CLAUDE_PROJECT_DIR="$p" bash "$GATE" feat --roster architect,qa 2>/dev/null ); rc=$?
assert "roster-flag-two-roles-pass" "[ $rc -eq 0 ]"

# --- bad input: non-integer CHANGE_CYCLE → exit 1 ---
p=$(new_proj badcycle 1); printf 'PHASE: CHANGE_REVIEW\nCHANGE_CYCLE: two\n' > "$p/.sdd/feat/PROGRESS.md"
run "$p"
assert "non-integer-cycle-exit-1" "[ $rc -eq 1 ]"

# --- bad input: missing PROGRESS → exit 1; flag-looking slug → exit 1 ---
p="$work/noprog"; mkdir -p "$p/.sdd/feat"
run "$p"
assert "no-progress-exit-1" "[ $rc -eq 1 ]"
out=$( bash "$GATE" --roster architect,qa 2>/dev/null ); rc=$?
assert "dash-slug-exit-1" "[ $rc -eq 1 ]"

# --- review focus: a product-owner id (role name with a hyphen) is demoted at cycle 2 like any other ---
p=$(new_proj poid 2); cblock "$p" 2 product-owner '- [major] (product-owner-cc2-1) wording of AC-9 could be tighter' '  disposition: fix'; cblock "$p" 2 qa; cblock "$p" 2 architect
run "$p"
assert "hyphenated-role-id-demoted" "[ $rc -eq 0 ] && printf '%s' \"\$out\" | grep -q '\"demoted\":\\[\"product-owner-cc2-1\"\\]'"

# --- review focus: a blank line between a major and its disposition ends the run; the major reads OPEN (fails closed) ---
p=$(new_proj blank 1); cblock "$p" 1 product-owner; cblock "$p" 1 qa; cblock "$p" 1 architect '- [major] (architect-cc1-1) x' '' '  disposition: adr ADR-4'
run "$p"
assert "blank-line-ends-run-fails-closed" "[ $rc -eq 2 ] && printf '%s' \"\$out\" | grep -q majors-open"

# --- review focus: REVIEW.md absent → every role missing, exit 2, no crash ---
p=$(new_proj noreview 1); rm "$p/.sdd/feat/REVIEW.md"
run "$p"
assert "no-review-file-refuses" "[ $rc -eq 2 ] && printf '%s' \"\$out\" | grep -q missing-architect && printf '%s' \"\$out\" | grep -q missing-qa"

# --- review focus: DECISIONS.md absent while a major cites an ADR → majors-without-adr ---
p=$(new_proj nodecisions 1); rm "$p/.sdd/feat/DECISIONS.md"; cblock "$p" 1 product-owner; cblock "$p" 1 qa; cblock "$p" 1 architect '- [major] (architect-cc1-1) x' '  disposition: adr ADR-4'
run "$p"
assert "no-decisions-file-refuses" "[ $rc -eq 2 ] && printf '%s' \"\$out\" | grep -q majors-without-adr"

# --- review focus: CRLF PROGRESS.md still parses CHANGE_CYCLE ---
p=$(new_proj crlf 1); printf 'PHASE: CHANGE_REVIEW\r\nCHANGE_CYCLE: 1\r\n' > "$p/.sdd/feat/PROGRESS.md"; cblock "$p" 1 product-owner; cblock "$p" 1 qa; cblock "$p" 1 architect
run "$p"
assert "crlf-progress-parses" "[ $rc -eq 0 ]"

echo "-----"; echo "passed=$pass failed=$fail"; [ "$fail" -eq 0 ]
