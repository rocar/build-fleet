#!/usr/bin/env bash
# Tests for hooks/scripts/validate-acceptance-count.sh (PostToolUse criterion cap on the
# spec's acceptance section, driven by AC_MAX; absent field = no cap).
# Run: bash hooks/scripts/validate-acceptance-count.test.sh   (exit 0 = all pass)
set -uo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK="$DIR/validate-acceptance-count.sh"
work="$(mktemp -d)"; trap 'rm -rf "$work"' EXIT
pass=0; fail=0
new_proj() { local p="$work/$1"; mkdir -p "$p/.sdd/feat"; printf 'feat\n' > "$p/.sdd/ACTIVE"; printf 'SDD_SCHEMA: 2\nPHASE: SPEC\nAC_MAX: %s\n' "$2" > "$p/.sdd/feat/PROGRESS.md"; printf '%s' "$p"; }
# spec <proj> [slug] — spec.md: STATUS, a narrative section naming AC-99, then stdin under ## Acceptance Criteria
spec() { local d="$1/.sdd/${2:-feat}"; mkdir -p "$d"; { printf 'STATUS: DRAFT\n\n# Spec\n\n## Behaviour\n\nSee AC-99 in prose.\n\n## Acceptance Criteria\n\n'; cat; } > "$d/spec.md"; }
check() { local name="$1" proj="$2" fp="$3" want="$4" rc=0; ( cd "$proj" && printf '{"tool_input":{"file_path":"%s"}}' "$fp" | CLAUDE_PROJECT_DIR="$proj" bash "$HOOK" >/dev/null 2>&1 ); rc=$?; if [ "$rc" -eq "$want" ]; then pass=$((pass+1)); printf 'ok   %-40s rc=%s\n' "$name" "$rc"; else fail=$((fail+1)); printf 'FAIL %-40s want=%s got=%s\n' "$name" "$want" "$rc"; fi; }
check_err() { local name="$1" proj="$2" fp="$3" needle="$4" rc=0 err; err=$( cd "$proj" && printf '{"tool_input":{"file_path":"%s"}}' "$fp" | CLAUDE_PROJECT_DIR="$proj" bash "$HOOK" 2>&1 >/dev/null ); rc=$?; if [ "$rc" -eq 2 ] && printf '%s' "$err" | grep -qi -- "$needle"; then pass=$((pass+1)); printf 'ok   %-40s rc=2\n' "$name"; else fail=$((fail+1)); printf 'FAIL %-40s got=%s (%s)\n' "$name" "$rc" "$err"; fi; }
S=".sdd/feat/spec.md"

p=$(new_proj under 3); printf -- '- **AC-1** a\n- **AC-2** b\n' | spec "$p"
check "under-cap-allows" "$p" "$S" 0
p=$(new_proj over 3); printf -- '- **AC-1** a\n- **AC-2** b\n- **AC-3** c\n- **AC-3a** d\n' | spec "$p"
check "over-cap-refuses" "$p" "$S" 2
check_err "over-cap-names-count" "$p" "$S" "4 distinct"
check_err "over-cap-names-cap" "$p" "$S" "AC_MAX of 3"
check_err "message-says-split" "$p" "$S" "SPLIT"
check_err "message-split-route" "$p" "$S" "backlog row"
p=$(new_proj rep 3); printf -- '- AC-1 a\n- AC-2 b\n- AC-2 repeated\n- see AC-1 again\n' | spec "$p"
check "repeats-count-once" "$p" "$S" 0
p=$(new_proj prose 3); printf -- '- AC-1\n- AC-2\n- AC-3\n' | spec "$p"
check "prose-ids-outside-section-ignored" "$p" "$S" 0
p=$(new_proj sub 3); printf '### Import\n\n- AC-1\n- AC-2\n\n### Export\n\n- AC-3\n- AC-4\n' | spec "$p"
check "criteria-subsections" "$p" "$S" 2
p=$(new_proj later 3); printf -- '- AC-1\n\n## Self-review notes\n\nAC-5 AC-6 AC-7 AC-8\n' | spec "$p"
check "later-section-ends-it" "$p" "$S" 0
p=$(new_proj crlf 3); printf -- '- AC-1\r\n- AC-2\r\n- AC-3\r\n- AC-4\r\n' | spec "$p"
check_err "criteria-crlf" "$p" "$S" "4 distinct"
p=$(new_proj acc 3); printf 'AC-1\nAC-2\nAC-3\nAC-4\nAC-5\n' > "$p/.sdd/feat/acceptance.md"
check "acceptance-md-not-a-trigger" "$p" ".sdd/feat/acceptance.md" 0
check "absent-file-allows" "$p" ".sdd/other/spec.md" 0
p=$(new_proj g 3); printf 'PHASE: SPEC\n' > "$p/.sdd/feat/PROGRESS.md"; printf -- '- AC-1\n- AC-2\n- AC-3\n- AC-4\n- AC-5\n' | spec "$p"
check "no-cap-field" "$p" "$S" 0
p=$(new_proj z 0); printf -- '- AC-1\n- AC-2\n- AC-3\n- AC-4\n' | spec "$p"
check "zero-disables" "$p" "$S" 0
p=$(new_proj bad 3x); printf -- '- AC-1\n' | spec "$p"
check "garbage-cap" "$p" "$S" 2
check_err "garbage-cap-message" "$p" "$S" "AC_MAX is not an integer"
p=$(new_proj prod 1); printf -- '- AC-1\n- AC-2\n- AC-3\n' | spec "$p" _product
check "product-tier-exempt" "$p" ".sdd/_product/spec.md" 0
p=$(new_proj t 1); mkdir -p "$p/docs"; printf '## Acceptance\n\nAC-1\nAC-2\n' > "$p/docs/spec.md"
check "outside-sdd-ignored" "$p" "docs/spec.md" 0
rc=0; ( cd "$p" && printf 'not json' | CLAUDE_PROJECT_DIR="$p" bash "$HOOK" >/dev/null 2>&1 ); rc=$?
if [ "$rc" -eq 2 ]; then pass=$((pass+1)); echo "ok   malformed-json-fails-closed"; else fail=$((fail+1)); echo "FAIL malformed-json-fails-closed got=$rc"; fi
echo "-----"; echo "passed=$pass failed=$fail"; [ "$fail" -eq 0 ]
