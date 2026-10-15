#!/usr/bin/env bash
# Agent and skill surface guard (docs/history/2026-10-16-lean-agents.md §3.3):
#   descriptions are one line, at most 40 words, name no hidden step, and (agents) say
#   "Do NOT use"; agent bodies fit their word cap; tools: allowlists never widen; every
#   line of the rules inventory is checked off.
# Run: bash scripts/agent-surface.test.sh   (exit 0 = all pass)
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
pass=0; fail=0
ok() { pass=$((pass+1)); printf 'ok   %s\n' "$1"; }
no() { fail=$((fail+1)); printf 'FAIL %s — %s\n' "$1" "$2"; }

# Agents whose bodies and descriptions are not cut yet; each lean task removes its name.
PENDING="architect classifier product-owner scribe skill:adr skill:review-rubric skill:sdd-diagnosis-template skill:sdd-protocol skill:sdd-spec-template skill:skill-routing skill:test-plan"

# Body caps: name:cap:reason. Absent ⇒ 800.
CAPS="
qa:1433:mirrored rubric, verified rule and lens (about 300 words) plus the counterfactual snapshot procedure
"
# Recorded allowlists (exact, order included). A deliberate change edits this line too.
TOOLS="
architect:Read, Grep, Glob, Edit
classifier:Read, Grep, Glob
coder:Read, Grep, Glob, Edit, Write, Bash
devops:Read, Grep, Glob, Edit, Write, Bash
product-owner:Read, Grep, Glob, Edit, Write
qa:Read, Grep, Glob, Edit, Write, Bash
reviewer:Read, Grep, Glob
scribe:Read, Write, Edit
"
fm() { awk -v k="$2" '/^---$/{n++; next} n==1 && index($0, k ":") == 1 { v = substr($0, length(k) + 2); sub(/^[ \t]+/, "", v); print v; exit }' "$1"; }
words() { printf '%s\n' "$1" | awk '{ for (i = 1; i <= NF; i++) if ($i != "|") w++ } END { print w + 0 }'; }
body_words() { awk '/^---$/{n++; next} n>=2' "$1" | awk '{ for (i = 1; i <= NF; i++) if ($i != "|") w++ } END { print w + 0 }'; }
pending() { case " $PENDING " in *" $1 "*) return 0 ;; esac; return 1; }

check_desc() {  # <file> <name> <agent?>
  local d n; d=$(fm "$1" description)
  case "$d" in ''|'>'*|'|'*) no "$2 description one line" "missing or folded"; return ;; esac
  n=$(words "$d")
  if [ "$n" -le 40 ]; then ok "$2 description <= 40 words ($n)"; else no "$2 description <= 40 words" "$n words"; fi
  case "$d" in *'/build-fleet:'*) no "$2 description names no hidden step" "contains /build-fleet:" ;; *) ok "$2 description names no hidden step" ;; esac
  if [ "$3" = agent ]; then
    case "$d" in *'Do NOT use'*) ok "$2 description says Do NOT use" ;; *) no "$2 description says Do NOT use" "missing" ;; esac
  fi
}

for f in "$ROOT"/agents/*.md; do
  a=$(basename "$f" .md)
  want=$(printf '%s\n' "$TOOLS" | awk -F: -v a="$a" '$1 == a { print substr($0, length(a) + 2) }')
  got=$(fm "$f" tools)
  if [ -n "$want" ] && [ "$got" = "$want" ]; then ok "$a tools pinned"; else no "$a tools pinned" "want [$want] got [$got]"; fi
  if pending "$a"; then continue; fi
  check_desc "$f" "$a" agent
  cap=$(printf '%s\n' "$CAPS" | awk -F: -v a="$a" '$1 == a { print $2 }'); [ -n "$cap" ] || cap=800
  n=$(body_words "$f")
  if [ "$n" -le "$cap" ]; then ok "$a body <= $cap words ($n)"; else no "$a body <= $cap words" "$n words"; fi
done
for f in "$ROOT"/skills/*/SKILL.md; do
  s=$(basename "$(dirname "$f")")
  pending "skill:$s" && continue
  check_desc "$f" "skill $s" skill
done
# Rules inventory: "- [ ] <agent> R<n>: "<old>"" before the cut; "- [x] <agent> R<n>:
# "<old>" → "<new>"" after it. Every [x] line's <new> quote must appear verbatim on one
# line of that agent's file; no [ ] line may remain for an agent that is not pending.
inv="$ROOT/docs/history/2026-10-16-lean-agents-RULES.md"
if [ -f "$inv" ]; then
  bad=0; n=0
  while IFS= read -r line; do
    a=$(printf '%s' "$line" | sed -E 's/^- \[[ x]\] ([^ ]+) .*/\1/')
    case "$line" in
      '- [ ] '*) pending "$a" || { no "rule kept: $line" "unchecked"; bad=1; } ;;
      '- [x] '*)
        n=$((n+1))
        q=$(printf '%s' "$line" | sed -n 's/.*→ "\(.*\)"[[:space:]]*$/\1/p')
        if [ -z "$q" ] || [ ! -f "$ROOT/agents/$a.md" ] || ! grep -qF -- "$q" "$ROOT/agents/$a.md"; then
          no "rule kept: $line" "new quote not found in agents/$a.md"; bad=1
        fi ;;
    esac
  done < "$inv"
  [ "$bad" -eq 0 ] && ok "rules inventory: $n checked, all found"
fi

printf '\npassed=%d failed=%d\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
