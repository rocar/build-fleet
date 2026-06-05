#!/usr/bin/env bash
# Shared helpers for build-fleet hooks. Source from each script. Hooks run
# with the target project's cwd, so all paths below are relative to cwd.

# Require jq for JSON parsing. If absent, exit 0 (allow) and warn — we do
# not want to block work because of a missing tool. A sourced `exit` ends
# the calling script process, which is the intent here.
require_jq() {
  if ! command -v jq >/dev/null 2>&1; then
    echo "build-fleet: jq not found; hook checks disabled. Install jq to enable enforcement." >&2
    exit 0
  fi
}

# Echo the active feature slug, or empty string if none.
resolve_active() {
  local active_file=".sdd/ACTIVE"
  [ -f "$active_file" ] || return 0
  head -n1 "$active_file" 2>/dev/null | tr -d '[:space:]'
}

# Echo a field value from .sdd/<slug>/PROGRESS.md.
# Usage: read_progress_field <slug> <field>
read_progress_field() {
  local slug="$1" field="$2"
  local f=".sdd/${slug}/PROGRESS.md"
  [ -f "$f" ] || return 0
  { grep -m1 "^${field}:" "$f" 2>/dev/null || true; } \
    | sed -E "s/^${field}:[[:space:]]*//" \
    | tr -d '\r '
}

# Echo the product slug if a product tier is engaged, else empty string.
# (v0.4 product tier — mirrors resolve_active.) Reads the .sdd/PRODUCT marker
# written by /build-fleet:new-product; falls back to the PRODUCT: field of
# .sdd/_product/PROGRESS.md for tiers scaffolded before the marker existed.
# DORMANT in M3.0 — no gate keys off it yet; M3.1/M3.2 wire it in.
resolve_product() {
  local marker=".sdd/PRODUCT"
  if [ -f "$marker" ]; then
    head -n1 "$marker" 2>/dev/null | tr -d '[:space:]'
    return 0
  fi
  local prog=".sdd/_product/PROGRESS.md"
  [ -f "$prog" ] || return 0
  { grep -m1 "^PRODUCT:" "$prog" 2>/dev/null || true; } \
    | sed -E 's/^PRODUCT:[[:space:]]*//' \
    | tr -d '\r '
}

# Echo a field value from .sdd/_product/PROGRESS.md.
# Usage: read_product_field <field>   (e.g. PHASE, SIZE)  — DORMANT in M3.0.
read_product_field() {
  local field="$1"
  local f=".sdd/_product/PROGRESS.md"
  [ -f "$f" ] || return 0
  { grep -m1 "^${field}:" "$f" 2>/dev/null || true; } \
    | sed -E "s/^${field}:[[:space:]]*//" \
    | tr -d '\r '
}

# Echo the spec STATUS value (DRAFT|IN_REVIEW|FINALIZED|BLOCKED) for the
# active feature, or empty if spec.md or its STATUS line is absent.
# Usage: read_spec_status <slug>
read_spec_status() {
  local slug="$1"
  local f=".sdd/${slug}/spec.md"
  [ -f "$f" ] || return 0
  { head -n30 "$f" 2>/dev/null | grep -m1 "^STATUS:" || true; } \
    | sed -E 's/^STATUS:[[:space:]]*//' \
    | tr -d '\r '
}

# --- Troubleshoot-fix bug lane (v0.5 M0 foundations — DORMANT until M2) ---
# The bug lane's source-of-truth artifact is diagnosis.md (the analog of spec.md).
# These mirror the forward-machine resolvers. No M0 hook keys off them; M2 wires
# read_diagnosis_status + resolve_lane into block-source-before-finalized's second
# unlock and require-reproducing-test.sh, which also consumes tests_exist. Added in
# foundations, same dormant-helper pattern as resolve_product/read_product_field.

# Echo the diagnosis STATUS (REPORTED|REPRODUCING|DIAGNOSED|CONFIRMED|FIXED) for the
# active bug, or empty if diagnosis.md or its STATUS line is absent. Mirrors
# read_spec_status. Usage: read_diagnosis_status <slug>
read_diagnosis_status() {
  local slug="$1"
  local f=".sdd/${slug}/diagnosis.md"
  [ -f "$f" ] || return 0
  { head -n30 "$f" 2>/dev/null | grep -m1 "^STATUS:" || true; } \
    | sed -E 's/^STATUS:[[:space:]]*//' \
    | tr -d '\r '
}

# Echo "bug" if the slug's workspace carries a diagnosis.md (the bug lane's
# source-of-truth artifact), else "feature". Presence of diagnosis.md is the
# structural discriminator; the PROGRESS `LANE:` field is the parseable mirror.
# Usage: resolve_lane <slug>
resolve_lane() {
  local slug="$1"
  if [ -f ".sdd/${slug}/diagnosis.md" ]; then
    printf 'bug'
  else
    printf 'feature'
  fi
}

# Return 0 if at least one regular file exists under tests/, else 1. The
# reproducing-test precondition for M2's require-reproducing-test.sh: a bug source
# write requires a reproduction to already exist. Usage: tests_exist
tests_exist() {
  [ -d tests ] || return 1
  [ -n "$(find tests -type f 2>/dev/null | head -n1)" ]
}

# Return 0 if the path lives anywhere under .sdd/.
# Usage: path_in_sdd <file_path>
# Matches relative forms plus both the symlinked ($PWD) and physical (pwd -P)
# absolute cwd — necessary because a caller may address files via the canonical
# path (e.g. macOS /tmp -> /private/tmp) while $PWD holds the symlinked form.
path_in_sdd() {
  local p="$1"
  local phys; phys=$(pwd -P 2>/dev/null)
  case "$p" in
    .sdd/*|./.sdd/*|"$PWD/.sdd/"*|"$phys/.sdd/"*) return 0 ;;
    *) return 1 ;;
  esac
}

# Return 0 if the path lives under .sdd/<slug>/ specifically.
# Usage: path_in_active_sdd <file_path> <slug>
# Same symlinked-vs-physical cwd handling as path_in_sdd.
path_in_active_sdd() {
  local p="$1" slug="$2"
  local phys; phys=$(pwd -P 2>/dev/null)
  case "$p" in
    .sdd/"${slug}"/*|./.sdd/"${slug}"/*|"$PWD/.sdd/${slug}/"*|"$phys/.sdd/${slug}/"*) return 0 ;;
    *) return 1 ;;
  esac
}

# Return 0 if the path lives under tests/ (the bug lane's reproducing-test home,
# always writable — even before CONFIRMED). Mirrors path_in_sdd's relative +
# symlinked/physical-cwd handling. Usage: path_in_tests <file_path>
path_in_tests() {
  local p="$1"
  local phys; phys=$(pwd -P 2>/dev/null)
  case "$p" in
    tests/*|./tests/*|"$PWD/tests/"*|"$phys/tests/"*) return 0 ;;
    *) return 1 ;;
  esac
}
