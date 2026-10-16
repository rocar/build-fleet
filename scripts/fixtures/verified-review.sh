# scripts/fixtures/verified-review.sh — shared fixture builders for the verified-review
# suites (quote-check, check-review-quotes, finalize-gate verified cases, review-carry,
# e2e). Source it after setting $work. bash 3.2.

VR_REASON='The constraints section caps retries at three attempts explicitly.'

# vr_proj <name> <cycle> [<cycle_total>] → project with feature 'feat', roster qa,architect
vr_proj() {
  local p="$work/$1"
  mkdir -p "$p/.sdd/feat"
  printf 'feat\n' > "$p/.sdd/ACTIVE"
  printf 'SDD_SCHEMA: 2\nFEATURE: feat\nPHASE: REVIEW\nCYCLE: %s\nCYCLE_TOTAL: %s\nREVIEW_ROLES: qa,architect\nREVIEW_SHAPE: verified\n' "$2" "${3:-$2}" > "$p/.sdd/feat/PROGRESS.md"
  printf 'STATUS: DRAFT\n# Upload\n## Behavior\nWhen offline, the client retries failed uploads.\n## Constraints\n*Retries* are capped at 3 attempts.\n## Acceptance Criteria\n- **AC-1**: an upload against a failing server stops after 3 attempts\n' > "$p/.sdd/feat/spec.md"
  printf '# Architecture Decisions — feat\n\n## ADR-1: keep retries client-side\n\n- **Status:** accepted\n' > "$p/.sdd/feat/DECISIONS.md"
  printf '# Review Log — feat\n\n' > "$p/.sdd/feat/REVIEW.md"
  printf '%s' "$p"
}
# vr_block <proj> <cycle> <role> <lines…> → append a verified block
vr_block() {
  local p="$1" c="$2" r="$3"; shift 3
  { printf '## Cycle %s — %s — 2026-10-20T00:00:00Z\nshape: verified\n' "$c" "$r"
    for l in "$@"; do printf '%s\n' "$l"; done
    printf '\n'; } >> "$p/.sdd/feat/REVIEW.md"
}
vr_up()  { printf '  verdict: {"v":%s,"vote":"uphold","severity":"%s"}' "$1" "$2"; }
# vr_rf <v> <quote-text> → a refutation with evidence quoting <quote-text> from spec.md
vr_rf()  { printf '  verdict: {"v":%s,"vote":"refute","severity":"minor","reason":"%s","quote":{"file":"spec.md","text":"%s"}}' "$1" "$VR_REASON" "$2"; }
vr_q()   { printf '  quote: {"file":"spec.md","text":"%s"}' "$1"; }
