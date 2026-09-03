#!/usr/bin/env bash
# Lens-drift test (v0.9). The review lenses for architect, qa and coder live in each
# role agent's "## Review lens" section (used on non-workflow paths) AND in
# workflows/review.js's LENS map (injected into the read-only reviewer agent in
# workflow REVIEW). This test extracts both and fails the suite if they drift —
# the rubric-drift pattern applied to lenses. Skips if node is absent. bash 3.2.
# Run: bash scripts/lens-drift.test.sh   (exit 0 = all agree)
set -uo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$DIR/.." && pwd)"
REVIEW="$ROOT/workflows/review.js"

if ! command -v node >/dev/null 2>&1; then
  echo "ok   lens-drift (SKIPPED: node not found; enforced in CI)"
  exit 0
fi

TMP="$(mktemp -d "${TMPDIR:-/tmp}/lens-drift.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
pass=0; fail=0

# The bullet list under "## Review lens" (bullets + their indented continuations),
# whitespace-normalized.
agent_lens() {
  awk '
    /^## Review lens/ { grab = 1; next }
    grab && /^## /    { exit }
    grab && /^- /     { inlist = 1 }
    grab && inlist && (/^- / || /^  /) { print }
  ' "$1" | tr -s '[:space:]' ' ' | sed -E 's/^ //; s/ $//'
}

awk '/LENS START/{f=1;next} /LENS END/{f=0;next} f' "$REVIEW" > "$TMP/lens.js"
if [ ! -s "$TMP/lens.js" ]; then echo "FAIL could not extract LENS region from $REVIEW"; exit 1; fi
cat "$TMP/lens.js" - > "$TMP/dump.js" <<'JS'
for (const k of Object.keys(LENS)) console.log(k + "\t" + LENS[k].replace(/\s+/g, " ").trim());
JS
node "$TMP/dump.js" > "$TMP/lens.tsv"

for role in architect qa coder; do
  want=$(agent_lens "$ROOT/agents/$role.md")
  got=$(grep "^$role	" "$TMP/lens.tsv" | cut -f2-)
  name="lens-matches-$role"
  if [ -z "$want" ]; then fail=$((fail+1)); printf 'FAIL %-32s no "## Review lens" bullets in agents/%s.md\n' "$name" "$role"
  elif [ -z "$got" ]; then fail=$((fail+1)); printf 'FAIL %-32s no LENS.%s in review.js\n' "$name" "$role"
  elif [ "$want" = "$got" ]; then pass=$((pass+1)); printf 'ok   %-32s\n' "$name"
  else fail=$((fail+1)); printf 'FAIL %-32s drifted\n--- agent\n%s\n--- review.js\n%s\n' "$name" "$want" "$got"; fi
done

echo "-----"; echo "passed=$pass failed=$fail"; [ "$fail" -eq 0 ]
