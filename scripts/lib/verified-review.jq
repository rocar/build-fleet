# scripts/lib/verified-review.jq — the REVIEW_SHAPE: verified rules, shared by
# scripts/quote-check.sh and scripts/finalize-gate.sh. The JS twin lives in
# workflows/review.js (VERIFIED-RULES region); scripts/verified-vote-parity.test.sh
# keeps the two equal. Pure jq 1.6+, no I/O.

def vr_rank: if . == "blocker" then 2 elif . == "major" then 1 elif . == "minor" then 0 else -1 end;
def vr_sev: ["minor", "major", "blocker"][.];

# Normalisation applied to a quote and to the file it cites before an exact match.
def vr_norm:
  gsub("[‘’]"; "'") | gsub("[“”]"; "\"") | gsub("[–—]"; "-")
  | gsub("[*_`]"; "") | gsub("\\s+"; " ") | ltrimstr(" ") | rtrimstr(" ");

# Text of ONE "## Cycle N — role — ts" block → array of findings.
# A continuation line ("  key: value") may be wrapped by hand: a following line indented
# 4+ spaces joins it (one space between) while its JSON value does not parse yet, and the
# joined value is parsed again. A value that parsed, or any other line, ends the join.
def vr_set_kv($k; $v):
  if $k == "verdict" then .cur.verdicts += [($v | (try fromjson catch {invalid: true}))]
  elif ($k == "quote" or $k == "absent" or $k == "closure" or $k == "carried" or $k == "demoted")
    then .cur[$k] = ($v | (try fromjson catch {invalid: true}))
  elif ($k == "ref" or $k == "test" or $k == "disposition") then .cur[$k] = $v
  else . end;
def vr_parse_block:
  split("\n")
  | reduce .[] as $l ({out: [], cur: null, kv: null};
      if ($l | test("^- \\[(blocker|major|minor)\\] \\(")) then
        (if .cur != null then .out += [.cur] else . end)
        | .kv = null
        | .cur = (($l | capture("^- \\[(?<severity>blocker|major|minor)\\] \\((?<id>[^)]+)\\) ?(?<text>.*)$")) + {verdicts: []})
      elif .cur != null and ($l | test("^  [a-z_]+: ")) then
        ($l | capture("^  (?<k>[a-z_]+): (?<v>.*)$")) as $kv
        | .kv = (if ($kv.k == "ref" or $kv.k == "test" or $kv.k == "disposition")
                   or ($kv.v | (try (fromjson | true) catch false)) then null else $kv end)
        | vr_set_kv($kv.k; $kv.v)
      elif .cur != null and .kv != null and ($l | test("^    +[^ ]")) then
        (.kv.v + " " + ($l | ltrimstr(" ") | sub("^ +"; ""))) as $joined
        | .kv.v = $joined
        | (if .kv.k == "verdict" then .cur.verdicts |= .[:-1] else . end)
        | vr_set_kv(.kv.k; $joined)
        | (if ($joined | (try (fromjson | true) catch false)) then .kv = null else . end)
      elif .cur != null and ($l | test("^[^ ]")) then .out += [.cur] | .cur = null | .kv = null
      else .kv = null end)
  | (if .cur != null then .out + [.cur] else .out end);

# Text of several blocks (split on "\n## ") → their findings, each tagged with its block's role.
def vr_parse_blocks:
  split("\n## ")
  | map(. as $b | ([$b | capture("^(## )?Cycle [0-9]+ (—|–|-) (?<r>[^ ]+)")] | .[0].r // null) as $r
        | vr_parse_block | map(. + {block_role: $r}))
  | add // [];

# Who raised a finding: the role prefix of a standard id (<role>-c<N>-<k>), else the role
# of the block it is written in (a hand-written free-form id).
def vr_raiser:
  if (.id | test("^[a-z][a-z-]*-c[0-9]+-[0-9]+$")) then (.id | sub("-c[0-9]+-[0-9]+$"; ""))
  else (.block_role // .id) end;

def vr_failed($fails; $id; $where; $v):
  any($fails[]; .id == $id and .where == $where and ((.v // null) == $v));

# A verdict's evidence counts: an object verdict with a quote {file,text}, a reason of
# at least 40 characters, and a quote the quote check did not fail.
def vr_evidence($fails; $id):
  (type == "object") and ((.invalid // false) | not)
  and ((.quote | type) == "object") and (((.quote.file // "") | tostring | length) > 0)
  and (((.quote.text // "") | tostring | length) > 0)
  and ((.reason | type) == "string") and ((.reason | length) >= 40)
  and (vr_failed($fails; $id; "verdict"; .v) | not);

# One finding → the finding plus {final, killed, closed, demoted_reason, reopened_closure}.
def vr_outcome($fails):
  . as $f
  | ($f.severity | vr_rank) as $orig
  # One verdict per verifier: only a panel verifier (v = 1, 2 or 3) votes, and a
  # repeated "v" keeps its first line (one voter, one vote). A line with no v, or a v
  # outside the panel, is not a vote.
  | (reduce (($f.verdicts // [])[] | select(type == "object" and ((.invalid // false) | not))
             | select(.v == 1 or .v == 2 or .v == 3)) as $x
       ({seen: {}, out: []};
        ($x.v | tostring) as $k | if .seen[$k] then . else .seen[$k] = true | .out += [$x] end) | .out) as $vs
  | ($vs | length) as $n
  | if ($f.carried != null) then
      $f + {final: $f.severity, killed: false, closed: false, demoted_reason: null, reopened_closure: false}
    elif ($f.closure != null) then
      ([$vs[] | select(.vote == "confirm")] | length) as $c
      | ($n >= 2 and $c * 2 > $n) as $voted
      | (vr_failed($fails; $f.id; "closure"; null)) as $qfail
      | $f + {final: $f.severity, killed: false, closed: ($voted and ($qfail | not)),
              demoted_reason: null, reopened_closure: ($voted and $qfail)}
    elif $orig < 1 then
      $f + {final: "minor", killed: false, closed: false, demoted_reason: null, reopened_closure: false}
    else
      ([$vs[] | select(.vote == "refute" and vr_evidence($fails; $f.id))] | length) as $r
      | ([$vs[] | (.severity | vr_rank) as $s
          | if ($s >= 0 and $s < $orig and vr_evidence($fails; $f.id)) then $s else $orig end] | sort) as $ranks
      | (if $n < 2 then $orig else $ranks[($n / 2 | floor)] end) as $med
      | ([$vs[] | select(.test_invalid == true)] | length) as $ti
      | (if (($f.demoted | type) == "object") then ($f.demoted.reason // "demoted")
         elif vr_failed($fails; $f.id; "anchor"; null) then "anchor-quote-failed"
         elif ($n >= 2 and $ti * 2 > $n) then "test-invalid"
         else null end) as $dem
      | $f + {killed: ($r >= 2), closed: false, demoted_reason: $dem, reopened_closure: false,
              final: (if $dem != null then "minor" else ([$med, $orig] | min | vr_sev) end)}
    end;

# After vr_outcome: why the finding is open, or null when it is not.
# $adrs: ADR numbers present in the feature DECISIONS.md.
def vr_open($adrs):
  if .killed or .closed then null
  elif .final == "blocker" then "blocker"
  elif .final == "major" then
    (if ((.disposition // "") | test("^adr ADR-0*[0-9]+"))
     then ((.disposition | capture("ADR-0*(?<n>[0-9]+)").n | tonumber) as $a
           | if ($adrs | index($a)) != null then null else "major-without-adr" end)
     else "major" end)
  else null end;

# Findings → the quotes to check. Carried entries are skipped: their evidence was
# checked in the cycle that raised them, against the spec as it was then. A closure
# claim's own anchor is skipped for the same reason (only its closure quote is new).
def vr_quotes:
  [ .[] | select(.carried == null) | . as $f
    | (($f.closure | type) == "object") as $cl
    | (if ($cl | not) and ($f.quote | type) == "object" then {id: $f.id, where: "anchor", file: $f.quote.file, text: $f.quote.text} else empty end),
      (if ($cl | not) and ($f.absent | type) == "object" then {id: $f.id, where: "anchor", file: $f.absent.file, section: ($f.absent.section // "")} else empty end),
      (if ($f.closure | type) == "object" then {id: $f.id, where: "closure", file: $f.closure.file, text: $f.closure.text} else empty end),
      (($f.verdicts // [])[] | select(type == "object" and (.quote | type) == "object")
        | {id: $f.id, where: "verdict", v: .v, file: .quote.file, text: .quote.text}) ];

# A cited file name as the quote sources are keyed: models often write the workspace
# path (".sdd/<slug>/spec.md", ".sdd/_product/DECISIONS.md"); map those to the keys.
# Another feature's path (".sdd/<other>/spec.md") maps to no key, so it fails.
def vr_file($slug):
  tostring | sub("^\\./"; "")
  | if startswith(".sdd/_product/") then ltrimstr(".sdd/")
    elif startswith(".sdd/" + $slug + "/") then ltrimstr(".sdd/" + $slug + "/")
    else . end;

# One quote item → true when it passes. $docs: {"spec.md": "<raw>", ...} — only
# allow-listed files that exist are present. $slug: the feature under review.
def vr_check($docs; $slug):
  (.file // "" | vr_file($slug)) as $file
  | ($docs[$file] // null) as $raw
  | if $raw == null then false
    elif (.section != null) then
      (.section | tostring | vr_norm | ascii_downcase | ltrimstr("§") | ltrimstr(" ")) as $s
      | ($s | length) > 0 and any($raw | split("\n")[] | select(test("^#{1,6} "))
            | sub("^#{1,6} +"; "") | vr_norm | ascii_downcase;
            . == $s or (sub("^[0-9.]+ +"; "") == $s))
    else
      (.text // "" | tostring | vr_norm) as $q
      | ($q | length) >= 10 and ($q | length) <= 500 and (($raw | vr_norm) | index($q)) != null
    end;

# Findings → ids reopened once failed quotes are applied.
def vr_revived($fails):
  [ .[] | (vr_outcome([])) as $a | vr_outcome($fails) as $b
    | select(($a.killed and ($b.killed | not))
             or (($b.final | vr_rank) > ($a.final | vr_rank))
             or ($a.closed and ($b.closed | not)))
    | .id ];
