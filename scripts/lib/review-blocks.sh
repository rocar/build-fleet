# scripts/lib/review-blocks.sh — REVIEW.md block helpers shared by
# scripts/finalize-gate.sh, scripts/quote-check.sh and scripts/review-carry.sh.
# Source it; bash 3.2 + BSD/GNU compatible; no side effects.

# Print the LAST "## Cycle <cycle> — <role> —" block of <review> (heading through
# the line before the next "## " heading, or EOF). Prints nothing when absent.
# Usage: last_cycle_block <review-file> <cycle> <role>
last_cycle_block() {
  local review="$1" cycle="$2" role="$3" start next end
  [ -f "$review" ] || return 0
  start=$({ grep -nE "^##[[:space:]]+Cycle[[:space:]]+${cycle}[[:space:]]+(—|–|-)[[:space:]]+${role}[[:space:]]+(—|–|-)" "$review" || true; } | tail -1 | cut -d: -f1)
  [ -n "$start" ] || return 0
  next=$({ tail -n +"$((start+1))" "$review" | grep -n '^## ' || true; } | head -1 | cut -d: -f1)
  if [ -n "$next" ]; then end=$((start+next-1)); else end=$(wc -l < "$review" | tr -d ' '); fi
  sed -n "${start},${end}p" "$review"
}

# Return 0 when a block (on stdin) is a verified-shape block: its second line is
# exactly "shape: verified".
block_is_verified() {
  [ "$(sed -n '2p' | tr -d '\r')" = "shape: verified" ]
}

# Echo the roles that have a "## Cycle <cycle> — <role> —" heading in <review>, one per
# line, first appearance first. Readers of verified blocks use this, not the roster: a
# --roles flag is not persisted, and a role may leave the roster with findings still open.
# Usage: cycle_roles <review-file> <cycle>
cycle_roles() {
  local review="$1" cycle="$2"
  [ -f "$review" ] || return 0
  { grep -E "^##[[:space:]]+Cycle[[:space:]]+${cycle}[[:space:]]+[^[:space:]]+[[:space:]]+[A-Za-z0-9_-]+[[:space:]]" "$review" || true; } \
    | sed -E "s/^##[[:space:]]+Cycle[[:space:]]+${cycle}[[:space:]]+[^[:space:]]+[[:space:]]+([A-Za-z0-9_-]+)[[:space:]].*/\1/" \
    | awk '!seen[$0]++'
}

# Print every verified block of <cycle> (each followed by a newline), whatever the roster.
# quote-check.sh hashes exactly this text and finalize-gate.sh re-reads it, so both must use it.
# Usage: verified_cycle_blocks <review-file> <cycle>
verified_cycle_blocks() {
  local review="$1" cycle="$2" r b
  for r in $(cycle_roles "$review" "$cycle"); do
    b=$(last_cycle_block "$review" "$cycle" "$r"); [ -n "$b" ] || continue
    printf '%s\n' "$b" | block_is_verified && printf '%s\n' "$b"
  done
  return 0
}

# Echo a JSON object of the allow-listed quote sources that exist for <slug>:
# {"spec.md": "<raw>", "DECISIONS.md": …, "_product/DECISIONS.md": …}
# Usage: quote_docs_json <slug>
quote_docs_json() {
  local slug="$1" out='{}' k p
  for k in spec.md DECISIONS.md _product/DECISIONS.md; do
    case "$k" in _product/*) p=".sdd/$k" ;; *) p=".sdd/${slug}/$k" ;; esac
    [ -f "$p" ] || continue
    out=$(jq -Rs --arg k "$k" --argjson acc "$out" '$acc + {($k): .}' "$p")
  done
  printf '%s' "$out"
}

# Echo the review-time fingerprint of the quote sources for <slug>, as JSON:
# spec.md hashed without its STATUS: line; each DECISIONS.md as
# {len, sha256} of its full content (the gate later checks that prefix).
# Usage: quote_docs_fingerprint <slug>
quote_docs_fingerprint() {
  local slug="$1" out='{}' k p h n
  for k in spec.md DECISIONS.md _product/DECISIONS.md; do
    case "$k" in _product/*) p=".sdd/$k" ;; *) p=".sdd/${slug}/$k" ;; esac
    [ -f "$p" ] || continue
    case "$k" in
      spec.md) h=$(grep -v '^STATUS:' "$p" | sha256_stdin); out=$(jq -cn --argjson a "$out" --arg k "$k" --arg h "$h" '$a + {($k): {sha256: $h}}') ;;
      *) n=$(wc -c < "$p" | tr -d ' '); h=$(sha256_stdin < "$p")
         out=$(jq -cn --argjson a "$out" --arg k "$k" --arg h "$h" --argjson n "$n" '$a + {($k): {len: $n, sha256: $h}}') ;;
    esac
  done
  printf '%s' "$out"
}

# Return 0 when the current quote sources still match a recorded fingerprint
# (spec.md without STATUS:, DECISIONS files: recorded prefix
# unchanged, appends allowed). Usage: fingerprint_matches <slug> '<fingerprint-json>'
fingerprint_matches() {
  local slug="$1" fp="$2" k p want n h
  for k in spec.md DECISIONS.md _product/DECISIONS.md; do
    want=$(printf '%s' "$fp" | jq -r --arg k "$k" '.[$k].sha256 // empty')
    [ -n "$want" ] || continue
    case "$k" in _product/*) p=".sdd/$k" ;; *) p=".sdd/${slug}/$k" ;; esac
    [ -f "$p" ] || return 1
    case "$k" in
      spec.md) h=$(grep -v '^STATUS:' "$p" | sha256_stdin) ;;
      *) n=$(printf '%s' "$fp" | jq -r --arg k "$k" '.[$k].len')
         [ "$(wc -c < "$p" | tr -d ' ')" -ge "$n" ] || return 1
         h=$(head -c "$n" "$p" | sha256_stdin) ;;
    esac
    [ "$h" = "$want" ] || return 1
  done
  return 0
}
