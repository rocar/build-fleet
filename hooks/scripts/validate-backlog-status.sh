#!/usr/bin/env bash
# PostToolUse (Write|Edit): when a write touches .sdd/_product/backlog.md, verify
# the load-bearing structure the product PLAN machine + M3.2 DEVELOPING loop parse:
# a PRODUCT: header, a valid STATUS line, and at least one phase heading.
#
# Keys strictly on basename==backlog.md under .sdd/_product/ — feature dirs have no
# backlog.md, so there is no collision with the feature tier (mirrors how
# validate-spec-status.sh keys on basename==spec.md).
#
# Deliberately lean: structural presence, not per-row grammar. A half-edited row
# should not hard-block the human mid-edit; what must stay intact is enough scaffold
# for resolve_product()/the loop to parse the file.
set -euo pipefail
# Fail CLOSED on any unexpected runtime error (audit §3.5); deliberate allows
# below are explicit exit 0.
trap 'echo "build-fleet: gate script errored unexpectedly — failing closed" >&2; exit 2' ERR

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./_lib.sh
. "$DIR/_lib.sh"

require_jq

input=$(cat)
file_path=$(extract_file_path "$input")
[ -n "$file_path" ] || exit 0

base=$(basename "$file_path")
[ "$base" = "backlog.md" ] || exit 0

# Only validate the product backlog (under .sdd/_product/). Anything else named
# backlog.md elsewhere is not ours.
case "$file_path" in
  *.sdd/_product/backlog.md) ;;
  *) exit 0 ;;
esac

[ -f "$file_path" ] || exit 0

# 1. PRODUCT: header.
if ! grep -Eq "^PRODUCT:[[:space:]]*\S" "$file_path"; then
  echo "build-fleet: _product/backlog.md missing 'PRODUCT: <slug>' header." >&2
  exit 2
fi

# 2. STATUS line present + valid.
status_line=$(head -n10 "$file_path" | grep -m1 "^STATUS:" || true)
if [ -z "$status_line" ]; then
  echo "build-fleet: _product/backlog.md missing STATUS line (within the first 10 lines). Must contain 'STATUS: DRAFT|IN_REVIEW|FINALIZED|BLOCKED'." >&2
  exit 2
fi

status_value=$(printf '%s' "$status_line" | sed -E 's/^STATUS:[[:space:]]*//' | tr -d '\r ')
case "$status_value" in
  DRAFT|IN_REVIEW|FINALIZED|BLOCKED) ;;
  *)
    echo "build-fleet: _product/backlog.md STATUS value '${status_value}' is invalid. Must be one of: DRAFT, IN_REVIEW, FINALIZED, BLOCKED." >&2
    exit 2
    ;;
esac

# 3. At least one phase heading: '## Phase <N>: ...'.
if ! grep -Eq "^##[[:space:]]+Phase[[:space:]]+[0-9]+:" "$file_path"; then
  echo "build-fleet: _product/backlog.md has no phase heading. Expected at least one line like '## Phase 1: <name> — STATUS: <state>'." >&2
  exit 2
fi

# 4. Intent byte cap (v0.9) — ONLY when the product PROGRESS carries INTENT_MAX_BYTES
# (absent ⇒ no cap; existing products are untouched; 0 disables). An intent is a
# sketch: what / boundary / non-goals in 1–3 lines. The tap pilot's intents grew to
# 2.5 KB each and seeded 500 KB specs. Measured by the shared extractor so this hook
# and /build-fleet:new-feature can never disagree on what an intent is.
max_bytes=$(read_product_field INTENT_MAX_BYTES)
case "$max_bytes" in ''|*[!0-9]*|0) exit 0 ;; esac
extractor="$DIR/../../scripts/intent-block.sh"
[ -f "$extractor" ] || exit 0
over=""
for slug in $({ grep -E '^[-*][[:space:]]+\[[ xX]\][[:space:]]+[A-Za-z0-9._-]+' "$file_path" || true; } | sed -E 's/^[-*][[:space:]]+\[[ xX]\][[:space:]]+([A-Za-z0-9._-]+).*/\1/'); do
  bytes=$({ bash "$extractor" --slug "$slug" "$file_path" 2>/dev/null || true; } | { grep -m1 '^INTENT_BYTES:' || true; } | sed -E 's/^INTENT_BYTES:[[:space:]]*//')
  case "$bytes" in ''|*[!0-9]*) continue ;; esac
  [ "$bytes" -gt "$max_bytes" ] && over="${over}${over:+, }${slug} (${bytes} bytes)"
done
if [ -n "$over" ]; then
  echo "build-fleet: _product/backlog.md intent block(s) exceed INTENT_MAX_BYTES=${max_bytes}: ${over}. An intent is a 1–3 line sketch (what / scope boundary / non-goals) — behaviour, interfaces and criteria belong in the feature spec. Cut the intent; do not raise the cap to land the write." >&2
  exit 2
fi

exit 0
