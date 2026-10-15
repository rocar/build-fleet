#!/usr/bin/env bash
# Tests for scripts/lite-next.sh — one fixture per routing row of the lite spec
# (docs/history/2026-10-15-lite.md §3.3) plus the failure rows (§4). Hermetic: each
# case builds a temp project and runs the router with CLAUDE_PROJECT_DIR pointing at it.
# Run: bash scripts/lite-next.test.sh   (exit 0 = all pass)
set -uo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROUTER="$DIR/lite-next.sh"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
pass=0; fail=0; n=0

# proj — a fresh project with an empty .sdd/ACTIVE; sets $P
proj(){ n=$((n+1)); P="$work/p$n"; mkdir -p "$P/.sdd"; : > "$P/.sdd/ACTIVE"; }
# feature <slug> <spec STATUS> — PROGRESS.md fields on stdin
feature(){
  mkdir -p "$P/.sdd/$1"; printf '%s\n' "$1" > "$P/.sdd/ACTIVE"
  printf 'STATUS: %s\n\n# Spec\n' "$2" > "$P/.sdd/$1/spec.md"
  { printf 'SDD_SCHEMA: 1\nFEATURE: %s\n' "$1"; cat; } > "$P/.sdd/$1/PROGRESS.md"
}
# bug <slug> [HYPOTHESIS_CYCLE] — PROGRESS.md fields on stdin
bug(){
  mkdir -p "$P/.sdd/$1"; printf '%s\n' "$1" > "$P/.sdd/ACTIVE"
  { printf 'STATUS: REPORTED\n\n# Bug: x\n\n## Root-cause hypothesis\n'
    [ -n "${2:-}" ] && printf 'HYPOTHESIS_CYCLE: %s\n' "$2"; } > "$P/.sdd/$1/diagnosis.md"
  { printf 'SDD_SCHEMA: 1\nFEATURE: %s\nLANE: bug\n' "$1"; cat; } > "$P/.sdd/$1/PROGRESS.md"
}
# product <PHASE> — a product tier, ratified backlog with one unblocked feature
product(){
  mkdir -p "$P/.sdd/_product"
  printf 'SDD_SCHEMA: 1\nPHASE: %s\nCYCLE: 1\n' "$1" > "$P/.sdd/_product/PROGRESS.md"
  printf 'PRODUCT: x\nSTATUS: FINALIZED\n\n## Phase 1: P1 — STATUS: pending\n- [ ] cli-skeleton   PENDING   depends-on: none\n' > "$P/.sdd/_product/backlog.md"
}
memory(){ printf '<!-- BEGIN build-fleet:product -->\nx\n<!-- END build-fleet:product -->\n' > "$P/CLAUDE.md"; }
# report <json> — a stub finalize gate that prints this report
report(){
  printf '%s\n' "$1" > "$P/report.json"
  printf '#!/usr/bin/env bash\nprintf "BUILD_FLEET_FINALIZE_REPORT: "; cat "%s"\n' "$P/report.json" > "$P/gate.sh"
}
OPEN='{"pass":false,"spec_changed":false,"open":[{"id":"a1"}]}'
run(){
  local g="$P/gate.sh"; [ -f "$g" ] || g="$DIR/finalize-gate.sh"
  (cd "$P" && CLAUDE_PROJECT_DIR="$P" BUILD_FLEET_FINALIZE_GATE="$g" bash "$ROUTER" "$@" 2>&1)
}
# check <name> <want-substring> <router args…>
check(){
  local name="$1" want="$2" out; shift 2
  out="$(run "$@")"
  if printf '%s' "$out" | grep -qF -- "$want"; then
    pass=$((pass+1)); printf 'ok   %s\n' "$name"
  else
    fail=$((fail+1)); printf 'FAIL %s\n     want[%s]\n     got [%s]\n' "$name" "$want" "$out"
  fi
}

# ---- start: nothing active ----
proj; check start-idea '"step":"new-feature","args":"add-csv-export add CSV export"' start add CSV export
proj; check start-idea-punctuation '"args":"add-csv-export-fast Add \"CSV\" export — fast!"' start 'Add "CSV" export — fast!'
proj; mkdir -p "$P/.sdd/add-csv-export"; check start-idea-collision '"args":"add-csv-export-2 add CSV export"' start add CSV export
proj; check start-idea-symbols-only '"stop":"nothing-to-do"' start '!!!'
proj; check start-nothing '"stop":"nothing-to-do"' start
proj; check start-product-new '"step":"new-product","args":"a-tiny-notes-app A tiny notes app"' start --product A tiny notes app
proj; check start-product-no-vision '"stop":"nothing-to-do"' start --product
proj; product PLAN; check start-product-plan '"step":"plan-review"' start
proj; product PLAN; check start-product-flag-existing '"step":"plan-review"' start --product again
proj; product PLAN_REVIEW; check start-plan-ready '"stop":"plan-ready","next":"/build-fleet:status ratify"' start
proj; product ESCALATED; check start-product-escalated '"stop":"escalated","next":"/build-fleet:status resolve <decision>"' start
proj; product DEVELOPING; check start-memory-missing '"step":"product-memory"' start
proj; product DEVELOPING; memory; check start-backlog-next '"step":"new-feature","args":"cli-skeleton"' start
proj; product DEVELOPING; memory
printf 'PRODUCT: x\nSTATUS: FINALIZED\n\n## Phase 1: P1 — STATUS: complete\n- [x] a   DONE   depends-on: none   handoff:2026-10-01\n' > "$P/.sdd/_product/backlog.md"
check start-backlog-complete '"stop":"nothing-to-do"' start

# ---- start: a feature in flight ----
proj; feature f DRAFT <<'EOF'
PHASE: SPEC
CYCLE: 0
TIER: standard
EOF
check start-first-review '"step":"review"' start
check start-idea-while-active '"stop":"item-in-flight","next":"/build-fleet:status park <reason>"' start another idea
proj; feature f DRAFT <<'EOF'
PHASE: SPEC
CYCLE: 0
TIER: trivial
EOF
check start-trivial '"stop":"spec-ready","next":"/build-fleet:build"' start
proj; feature f DRAFT <<'EOF'
PHASE: REVIEW
CYCLE: 1
TIER: standard
EOF
touch -t 202601010000 "$P/.sdd/f/spec.md"; printf 'x\n' > "$P/.sdd/f/REVIEW.md"; touch -t 202601010100 "$P/.sdd/f/REVIEW.md"
report "$OPEN"; check start-revise '"step":"revise"' start
report '{"pass":false,"spec_changed":true,"open":[{"id":"a1"}]}'; check start-re-review-verified '"step":"review"' start
report "$OPEN"; touch -t 202601010200 "$P/.sdd/f/spec.md"; check start-re-review-mtime '"step":"review"' start
report '{"pass":true,"spec_changed":false,"open":[]}'; check start-ready '"stop":"spec-ready","next":"/build-fleet:build"' start
printf '#!/usr/bin/env bash\nexit 1\n' > "$P/gate.sh"; check start-report-missing '"stop":"unknown-state"' start
proj; feature f FINALIZED <<'EOF'
PHASE: BUILD
CYCLE: 1
EOF
check start-finalized '"stop":"spec-ready","next":"/build-fleet:build"' start
proj; feature f DRAFT <<'EOF'
PHASE: WAT
CYCLE: 1
EOF
check start-unknown-phase '"stop":"unknown-state"' start
proj; feature f DRAFT <<'EOF'
PHASE: REVIEW
CYCLE: 1
EOF
: > "$P/.sdd/f/ESCALATION.md"; check start-escalated '"stop":"escalated","next":"/build-fleet:status resolve <decision>"' start
proj; feature f DRAFT <<'EOF'
PHASE: PARKED
CYCLE: 1
EOF
check start-parked '"stop":"parked"' start
proj; bug b <<'EOF'
PHASE: REPORT
CYCLE: 0
EOF
check start-while-bug '"stop":"item-in-flight"' start

# ---- build ----
proj; check build-nothing '"stop":"nothing-to-do","next":"/build-fleet:start"' build
proj; feature f DRAFT <<'EOF'
PHASE: REVIEW
CYCLE: 1
EOF
report "$OPEN"; check build-spec-not-ready '"stop":"spec-not-ready","next":"/build-fleet:start"' build
report '{"pass":true,"spec_changed":false,"open":[]}'; check build-finalize '"step":"finalize"' build
proj; feature f DRAFT <<'EOF'
PHASE: SPEC
CYCLE: 0
TIER: trivial
EOF
check build-trivial-finalize '"step":"finalize"' build
proj; feature f DRAFT <<'EOF'
PHASE: SPEC
CYCLE: 0
TIER: standard
EOF
check build-unreviewed '"stop":"spec-not-ready"' build
proj; feature f FINALIZED <<'EOF'
PHASE: BUILD
CYCLE: 1
EOF
check build-implement '"step":"implement"' build
proj; feature f FINALIZED <<'EOF'
PHASE: BUILD
BUILD_STATE: started
EOF
check build-resume-started '"step":"deep-build"' build
proj; feature f FINALIZED <<'EOF'
PHASE: BUILD
BUILD_STATE: needs-iteration
EOF
check build-needs-iteration '"step":"deep-build"' build
proj; feature f FINALIZED <<'EOF'
PHASE: BUILD
BUILD_STATE: done
EOF
check build-done '"stop":"built","next":"/build-fleet:ship"' build
proj; feature f FINALIZED <<'EOF'
PHASE: CHANGE_REVIEW
EOF
check build-legacy-past-build '"stop":"built","next":"/build-fleet:ship"' build
proj; bug b <<'EOF'
PHASE: FIX
EOF
check build-while-bug '"stop":"item-in-flight"' build

# ---- ship ----
proj; check ship-nothing '"stop":"nothing-to-do"' ship
proj; feature f FINALIZED <<'EOF'
PHASE: BUILD
BUILD_STATE: started
EOF
check ship-not-built '"stop":"not-built","next":"/build-fleet:build"' ship
proj; feature f FINALIZED <<'EOF'
PHASE: BUILD
BUILD_STATE: done
EOF
check ship-handoff '"step":"handoff"' ship
proj; feature f FINALIZED <<'EOF'
PHASE: HANDOFF
EOF
check ship-legacy-handoff '"step":"handoff"' ship
proj; bug b <<'EOF'
PHASE: HANDOFF
EOF
check ship-while-bug '"stop":"item-in-flight"' ship

# ---- fix ----
proj; check fix-triage '"step":"triage","args":"page 4 is missing"' fix page 4 is missing
proj; check fix-nothing '"stop":"nothing-to-do"' fix
proj; feature f DRAFT <<'EOF'
PHASE: SPEC
EOF
check fix-while-feature '"stop":"item-in-flight"' fix
proj; bug b <<'EOF'
PHASE: REPORT
CYCLE: 0
EOF
check fix-reproduce '"step":"reproduce"' fix
check fix-symptom-while-bug '"stop":"item-in-flight"' fix another symptom
proj; bug b <<'EOF'
PHASE: REPRODUCE
CYCLE: 0
EOF
check fix-first-hypothesis '"step":"action:hypothesis","args":"HYPOTHESIS_CYCLE: 1"' fix
proj; bug b 1 <<'EOF'
PHASE: REPRODUCE
CYCLE: 0
EOF
check fix-diagnose '"step":"diagnose"' fix
proj; bug b 1 <<'EOF'
PHASE: DIAGNOSE
CYCLE: 1
EOF
check fix-refuted '"step":"action:hypothesis","args":"HYPOTHESIS_CYCLE: 2"' fix
proj; bug b 1 <<'EOF'
PHASE: FIX
CYCLE: 1
FIX_CYCLE: 0
EOF
check fix-apply '"step":"apply-fix"' fix
proj; bug b 1 <<'EOF'
PHASE: FIX
FIX_CYCLE: 0
FIX_DONE_CYCLE: 0
EOF
check fix-verify '"step":"verify"' fix
proj; bug b 1 <<'EOF'
PHASE: FIX
FIX_CYCLE: 1
FIX_DONE_CYCLE: 0
EOF
check fix-after-bounce '"step":"apply-fix"' fix
proj; bug b 1 <<'EOF'
PHASE: HANDOFF
EOF
check fix-ship '"step":"ship-fix"' fix
proj; bug b 1 <<'EOF'
PHASE: VERIFY
EOF
check fix-verify-phase-unknown '"stop":"unknown-state"' fix
proj; bug b 1 <<'EOF'
PHASE: ESCALATED
EOF
check fix-escalated '"stop":"escalated"' fix

# ---- final-review fixes ----
proj; bug b 1 <<'EOF2'
PHASE: DIAGNOSE
CYCLE: 0
SEV: sev0
EOF2
sed -i.bak 's/^STATUS: REPORTED/STATUS: DIAGNOSED/' "$P/.sdd/b/diagnosis.md" && rm -f "$P/.sdd/b/diagnosis.md.bak"
check fix-sev0-fast-path '"step":"apply-fix"' fix
proj; product PLAN_REVIEW; printf 'x\n' > "$P/.sdd/_product/REVIEW.md"
touch -t 202601010000 "$P/.sdd/_product/REVIEW.md"; touch -t 202601010100 "$P/.sdd/_product/backlog.md"
check start-plan-edited-rereview '"step":"plan-review"' start
proj; feature f DRAFT <<'EOF2'
PHASE: REVIEW
CYCLE: 1
EOF2
touch -t 202601010000 "$P/.sdd/f/spec.md"; printf 'x\n' > "$P/.sdd/f/REVIEW.md"; touch -t 202601010100 "$P/.sdd/f/REVIEW.md"
report '{"pass":false,"spec_changed":false,"reasons":["missing-qa"],"open":[]}'
check start-review-gap-rereview '"step":"review"' start
report '{"pass":false,"spec_changed":false,"reasons":["open-blockers"],"open":[{"id":"a1"}]}'
check start-open-blockers-revise '"step":"revise"' start
proj; feature f FINALIZED <<'EOF2'
PHASE: BUILD
BUILD_STATE: done
EOF2
mkdir -p "$P/src/deep"
out="$(cd "$P/src/deep" && env -u CLAUDE_PROJECT_DIR bash "$ROUTER" build 2>&1)"
if printf '%s' "$out" | grep -qF '"stop":"built"'; then pass=$((pass+1)); echo "ok   subdir-finds-project"; else fail=$((fail+1)); echo "FAIL subdir-finds-project got[$out]"; fi

# the router must not force its C locale onto the finalize gate (UTF-8 block headings)
proj; feature f DRAFT <<'EOF2'
PHASE: REVIEW
CYCLE: 1
EOF2
touch -t 202601010000 "$P/.sdd/f/spec.md"; printf 'x\n' > "$P/.sdd/f/REVIEW.md"; touch -t 202601010100 "$P/.sdd/f/REVIEW.md"
cat > "$P/gate.sh" <<'EOF2'
#!/usr/bin/env bash
if [ "${LC_ALL:-}" = C ]; then
  echo 'BUILD_FLEET_FINALIZE_REPORT: {"pass":false,"spec_changed":false,"reasons":["missing-architect"],"open":[]}'
else
  echo 'BUILD_FLEET_FINALIZE_REPORT: {"pass":false,"spec_changed":false,"reasons":["majors-open"],"open":[{"id":"a1"}]}'
fi
EOF2
saved_lc="${LC_ALL-}"; export LC_ALL=en_US.UTF-8
check gate-keeps-caller-locale '"step":"revise"' start
if [ -n "$saved_lc" ]; then export LC_ALL="$saved_lc"; else unset LC_ALL; fi

# ---- status ----
proj; check status-nothing '"stop":"nothing-to-do"' status
proj; product PLAN_REVIEW; check status-plan-ready '"stop":"plan-ready"' status
proj; feature f DRAFT <<'EOF'
PHASE: SPEC
CYCLE: 0
EOF
check status-start '"stop":"status","next":"/build-fleet:start"' status
proj; feature f FINALIZED <<'EOF'
PHASE: BUILD
EOF
check status-build '"stop":"status","next":"/build-fleet:build"' status
proj; feature f FINALIZED <<'EOF'
PHASE: BUILD
BUILD_STATE: done
EOF
check status-ship '"stop":"status","next":"/build-fleet:ship"' status
proj; bug b <<'EOF'
PHASE: REPORT
EOF
check status-fix '"stop":"status","next":"/build-fleet:fix"' status

# ---- fail closed ----
proj; printf '../x\n' > "$P/.sdd/ACTIVE"; check active-traversal '"stop":"unknown-state"' start
proj; printf 'ghost\n' > "$P/.sdd/ACTIVE"; check active-no-progress '"stop":"unknown-state"' build
proj; mkdir -p "$P/.sdd/f"; printf 'f\r\n' > "$P/.sdd/ACTIVE"
printf 'STATUS: FINALIZED\r\n' > "$P/.sdd/f/spec.md"
printf 'SDD_SCHEMA: 1\r\nPHASE: BUILD\r\nBUILD_STATE: done\r\n' > "$P/.sdd/f/PROGRESS.md"
check crlf-progress '"stop":"built"' build
proj; nojq="$work/nojq"; mkdir -p "$nojq"
for c in bash awk tr sed cat cut dirname grep head; do ln -sf "$(command -v "$c")" "$nojq/$c"; done
out="$(cd "$P" && PATH="$nojq" CLAUDE_PROJECT_DIR="$P" "$nojq/bash" "$ROUTER" start 2>&1)"
if printf '%s' "$out" | grep -qF '"stop":"unknown-state"'; then pass=$((pass+1)); echo "ok   no-jq"; else fail=$((fail+1)); echo "FAIL no-jq got[$out]"; fi
# ---- drift repair: QA_FAIL: drift sends build to implement, stops ship ----
for bs in unset started needs-iteration done; do
  proj; { printf 'PHASE: BUILD\nQA_FAIL: drift\n'; [ "$bs" = unset ] || printf 'BUILD_STATE: %s\n' "$bs"; } | feature f FINALIZED
  check "build-drift-repair-$bs" '"step":"implement","args":"","why":"repair the test plan"' build
done
proj; feature f FINALIZED <<'EOF'
PHASE: HANDOFF
BUILD_STATE: done
QA_FAIL: drift
EOF
check ship-drift '"stop":"drift","next":"/build-fleet:build"' ship

rc=0; bash "$ROUTER" bogus >/dev/null 2>&1 || rc=$?
if [ "$rc" = 1 ]; then pass=$((pass+1)); echo "ok   bad-usage"; else fail=$((fail+1)); echo "FAIL bad-usage rc=$rc"; fi

echo "lite-next: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
