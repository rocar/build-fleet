# Dashboard — design

**Date:** 2026-10-14
**Status:** draft for review (design approved section by section in brainstorming); implementation plan follows approval
**Ships as:** two releases.
- **Part A, v0.12.0:** the gate event log, the `ref:` finding line, the gates' `--report`
  mode, and the `approval_status` helper (inert until a project opts in).
- **Part B, v0.13.0:** opt-in approvals as gate input, and the localhost dashboard.

**Supersedes:** the roadmap's 0.13 "static HTML views" item. `/build-fleet:status --html`
survives as the dashboard's export mode (§3.6).
**Independent of:** the 0.11 lite profile. This design targets today's command names and
files; where lite changes a file the linker reads, the linker reads both shapes (§3.5).
**Evidence:** roadmap review, section 6 (https://claude.ai/artifact/RjjQEmAJ6woyP1aGQXdK4j);
Claude Code channels and hooks references (code.claude.com/docs/en/channels-reference,
/hooks); prior art checked 2026-10-14: spec-workflow-mcp (4.3k stars, approval enforced
only by instruction), specdeck (edits files, never talks to the agent), Vibe Kanban
(orchestrator, no spec or gates).

## 1. Problem

| Symptom | Cause |
|---|---|
| Hard to see where a feature stands without opening several markdown files. | State is spread over spec.md, acceptance.md, REVIEW.md, DECISIONS.md and PROGRESS.md; `/build-fleet:status` is terminal text. |
| No record of what the gates decided. | Hooks refuse with exit 2 and stderr; gate scripts print signal lines to stdout. Nothing is persisted, so a refusal leaves no trace in the audit trail `.sdd/` is meant to be. |
| The links between artifacts are invisible. | Findings, ADRs, acceptance criteria and tests already carry stable ids (`qa-c1-2`, `ADR-3`, `AC-4`), but no tool follows them. A finding points at the spec only in free text. |
| A person cannot sign off at a checkpoint in a way the gates honour. | The only human approvals today are running a command. Nothing records who approved what content, and nothing stops an approval from silently covering content that changed afterwards. |

Competing dashboards show progress. build-fleet's edge is enforcement, so this dashboard
shows enforcement: every gate decision, every approval, and how spec, findings, ADRs and
tests link to each other. An approval is one more input a gate checks.

## 2. Decisions

| # | Decision | Rationale |
|---|---|---|
| D1 | **Three audiences, equally:** the developer at the keyboard, an approver away from the terminal, an evaluator reading the trail later. | Each maps to one layer: live view, approvals, event log. |
| D2 | **Hooks and gate scripts append to an event log; the dashboard only reads it** (plus `.sdd/` and git). | Rebuilding history from git cannot see refusals (they change no file). HTTP hooks lose events whenever the server is down and make hooks depend on an optional process. |
| D3 | **Approve writes a record that gates require; it does not drive the session.** Unattended runs stop at a checkpoint and resume by the next command or `/loop`. | Works with no session running. Live control needs channels, which are a research preview (custom channels need `--dangerously-load-development-channels`). |
| D4 | **Checkpoints are opt-in per project, off by default.** A terminal path approves too. | Today's flow is unchanged for everyone who does not opt in. The dashboard is one way to approve, not the only way. |
| D5 | **Localhost only, per-run token; remote access through the user's own tunnel.** | Smallest attack surface for a button that carries authority. |
| D6 | **Node, standard library only, for the dashboard.** Core build-fleet stays bash + jq. | One file, no install step, no npm dependencies. The later channel layer is JS too. |
| D7 | **One parser for gate semantics.** The dashboard gets finding status from the gate scripts' `--report` mode; its own linker is display-only. | Two parsers of REVIEW.md would drift. Gates decide; the linker only draws. |
| D8 | **Add an optional `ref:` continuation line to findings.** | The only way to anchor a finding to a spec section reliably. Gates ignore it. |
| D9 | **Approvals and the forgery guards are a tripwire, not a wall.** | The agent runs as the same user. The design catches casual or accidental forgery and leaves evidence; it does not claim more. |

## 3. Design

### 3.1 The event log (Part A)

**Files.**
- `.sdd/<slug>/EVENTS.jsonl` — one per feature or bug. Append-only, committed with the
  rest of the workspace.
- `.sdd/_events.jsonl` — committed; events with no workspace to land in (an
  `acquire-active` refusal, `new-feature` refusing an existing workspace).

**Schema `build-fleet/event@1`**, one JSON object per line:

```json
{"v":1,"ts":"2026-10-14T09:12:03Z","slug":"auth","kind":"gate","source":"hook:block-source-before-finalized","decision":"refuse","reason":"spec-not-finalized","detail":"Write src/auth.ts","ids":[]}
```

| Field | Values |
|---|---|
| `kind` | `gate` · `signal` · `phase` · `approval` |
| `source` | `hook:<script>` or `script:<script>` or `approve` |
| `decision` | `gate`: `allow`·`refuse`·`escalate`. `approval`: `approve`·`send-back`. Absent for `signal`/`phase`. |
| `reason` | kebab-case slug. Each hook gets fixed slugs for its refusals; gate scripts reuse their existing refusal reasons. |
| `ids` | finding / ADR / AC ids the event concerns (e.g. the open blockers a finalize refusal names), so the timeline can link them. |
| `phase` kind | adds `from`, `to`. |
| `approval` kind | adds `checkpoint`, `hash`, `by`, `via`, `comment` (§3.2). |

**What is logged.**
- **Hooks log refusals and escalations only.** Logging every allowed write would bury
  the log; allow is the default.
- **Gate scripts log both outcomes:** `finalize-gate.sh`, `change-review-gate.sh`,
  `acquire-active.sh`, and the Stop test gate (`stop-tests.sh`, including the escalation
  after 3 red stops). A pass is an audit fact.
- **`signal` events cover lines printed by scripts only.** `BUILD_FLEET_*` lines that the
  model prints from a command body never pass through `log_event` and are not captured.
  Audit completeness (§6) is measured over gate decisions, not over every signal line.
- **Phase changes:** a new PostToolUse hook, `hooks/scripts/record-phase.sh`, matches
  writes to `.sdd/<slug>/PROGRESS.md`, compares `PHASE` with the last `phase` event in
  that workspace, and appends one when it differs. **It ignores `.workflow-in-flight`**,
  unlike the gating hooks, because the scribe writes PROGRESS.md during workflow runs and
  those transitions are exactly what the timeline needs.

**`log_event` in `hooks/scripts/_lib.sh`.** Builds the line with jq, appends with `>>`.
**Logging never changes a decision:** if the append fails (no jq, unwritable file, bad
slug), the function writes one stderr note and returns 0. A gate that would refuse still
refuses; a gate that would allow still allows. This is the one deliberate exception to
"hooks fail closed" and is written into CLAUDE.md in the same release.

**Protecting the log.** A new PreToolUse rule refuses agent `Write`/`Edit`/`NotebookEdit`
to any `EVENTS.jsonl` or `_events.jsonl`. Hooks append through their own scripts, never
through the agent's tools.

### 3.2 Approvals as gate input (Part A helper, Part B behaviour)

**Opting in.** A new project-level file `.sdd/config.md`, `KEY: value` lines like
PROGRESS.md:

```
REQUIRE_APPROVAL: spec,ship
```

Absent file or absent field ⇒ no checkpoints, behaviour identical to today.

**Checkpoints.**

| Name | Feature lane | Bug lane |
|---|---|---|
| `spec` | before `STATUS: FINALIZED` (finalize) | before `diagnosis.md` `STATUS: CONFIRMED` (the flip in `/build-fleet:fix`) |
| `ship` | before handoff dispatches devops | before `/build-fleet:ship-fix` dispatches devops |

**The record** is an `approval` event in the workspace's `EVENTS.jsonl`:

```json
{"v":1,"ts":"…","slug":"auth","kind":"approval","source":"approve","checkpoint":"spec","decision":"approve","hash":"sha256:…","by":"Rocconno","via":"dashboard","comment":""}
```

`decision: send-back` requires a non-empty comment. `by` is `git config user.name`
(not a verified identity). `via` is `dashboard` or `terminal`.

**The hash binds the approval to the content seen.**
- `spec`: sha256 over `spec.md` then `acceptance.md` (feature) or `diagnosis.md` (bug),
  **with the `STATUS:` line removed**. Finalize and fix rewrite STATUS after the approval;
  including it would make every approval lapse the moment it is used.
- `ship`: sha256 over `git ls-tree -r HEAD` with every path under `.sdd/` filtered out —
  the committed source tree. `.sdd/` commits after approval (scribe, PROGRESS) do not
  lapse it. `approve.sh ship` refuses while non-`.sdd/` changes are uncommitted, so what
  is approved is exactly what is in git.

An approval **matches** when it is the latest `approval` event for that checkpoint, its
decision is `approve`, and its hash equals the hash recomputed now. Content changed after
approval ⇒ no match ⇒ the checkpoint waits again.

**One helper, every caller.** `approval_status <slug> <checkpoint>` in `_lib.sh` returns
`not-required`, `approved`, `awaiting` or `sent-back`, and prints the current hash.
`scripts/approval-check.sh` wraps it for commands and, when the result is `awaiting` or
`sent-back`, prints:

```
BUILD_FLEET_AWAITING_APPROVAL: {"slug":"auth","checkpoint":"spec","hash":"sha256:…","state":"awaiting"}
```

| Caller | Checkpoint | Effect when not approved |
|---|---|---|
| `scripts/finalize-gate.sh` | `spec` (feature) | refuses, reason `awaiting-approval`; logs the gate event |
| `scripts/change-review-gate.sh` | `ship` (feature) | prints no passing gate line ⇒ devops refuses (0.10.1 rule) |
| `commands/fix.md`, before the CONFIRMED flip | `spec` (bug) | runs `approval-check.sh`; stops without flipping |
| `commands/ship-fix.md`, before dispatching devops | `ship` (bug) | runs `approval-check.sh`; stops without dispatching |
| `hooks/scripts/block-source-before-finalized.sh` (backstop) | `spec` (feature) | blocks source writes even when STATUS reads FINALIZED |
| `hooks/scripts/require-reproducing-test.sh` (backstop) | `spec` (bug) | blocks source writes even when STATUS reads CONFIRMED |

The backstops make the checkpoint a hook gate rather than an instruction: hand-editing
`STATUS: FINALIZED` does not unlock source. The 0.10.1 bug-lane exemption in
`agents/devops.md` stays; for bugs the check sits upstream of devops, in `ship-fix`.

Part A ships the helper and the callers with `REQUIRE_APPROVAL` unset, so every caller
returns `not-required`. Part B adds `approve.sh`, the dashboard and the docs that tell
people to turn it on.

**Send-back.** Recorded as an approval event with the comment. `/build-fleet:status`
shows the latest send-back comment; `/build-fleet:revise` passes it to the product owner
as input; in the bug lane, `/build-fleet:diagnose` passes it to the diagnosis workflow on its re-run. The gate
keeps refusing until a new `approve` matches the revised content. Send-back is not
written into REVIEW.md.

**Approving from the terminal.** `scripts/approve.sh <checkpoint> [--send-back]`,
comment on stdin, run by the person with the `!` prefix (`! bash <plugin>/scripts/approve.sh spec`)
so it runs in their shell, not through the agent's tools. It recomputes the hash,
refuses `ship` with uncommitted source changes, and appends the event.

**Forgery tripwires.**
- `guard-bash-writes.sh` refuses agent Bash calls that invoke `approve.sh`, name
  `.dashboard.json`, or name `/api/approve`.
- The EVENTS write rule (§3.1).
- These stop a `curl` or a direct script call, not a `Read` of `.dashboard.json` or
  obfuscated shell. Every approval carries `via`, and every event is committed, so a
  forgery leaves evidence. The docs say plainly that this is a tripwire, not a wall.
  No signing key in v1: the agent can read any file the user can.

### 3.3 The `ref:` finding line (Part A)

An optional continuation line anchors a finding to the spec:

```
- [major] (qa-c1-2) Retry limit is unspecified
  ref: §Behavior, AC-3
  disposition: fix
```

Grammar: `ref:` followed by a comma-separated list of `§<Spec section heading>`, `AC-<n>`,
`ADR-<n>`, or a finding id. Optional; reviewers add it when a finding concerns a specific
place. It lands in `skills/review-rubric/SKILL.md` and its three mirrors
(`agents/architect.md`, `agents/qa.md`, `agents/reviewer.md`), and in the REVIEW.md
format block in `skills/sdd-protocol/SKILL.md`. `scripts/rubric-drift.test.sh` covers
the mirrors. Gates must ignore it: `finalize-gate.sh` scans continuation runs only for
`refuted-by:`/`disposition:`, so it should fall through; the plan proves that with
failing-first cases for `finalize-gate.sh`, `change-review-gate.sh` and
`check-review-written.sh`.

### 3.4 Gate `--report` mode (Part A)

`finalize-gate.sh --report` and `change-review-gate.sh --report` print one JSON object —
findings with id, severity, cycle, role, state (`open`, `refuted`, `fix`, `adr ADR-n`),
`ref` list, and the gate's verdict — and **log nothing and change nothing**. The dashboard
and `status-snapshot.sh` consume it. Gate decisions keep their existing signal lines.
`status-snapshot@1` gains `awaiting_approval` (additive; schema stays @1).

### 3.5 The dashboard server (Part B)

**Command.** `/build-fleet:dashboard` starts `node <plugin>/dashboard/server.mjs` in the
background for the current repo and prints
`BUILD_FLEET_DASHBOARD: {"url":"http://127.0.0.1:<port>/?t=<token>"}`. Port 4317, or the
next free. Run state (`pid`, `port`, `token`) in `.sdd/.dashboard.json`, gitignored.
Running it again reports the live server instead of starting a second. `--stop` ends it.
One repo per server.

**Data.**
- State: `status-snapshot.sh`.
- Findings and verdicts: the gates' `--report` mode (§3.4).
- Timeline: `EVENTS.jsonl` directly, plus `git log` subjects (the linker scans them for id mentions).
- Writes: approvals only, by running `approve.sh` via `execFile`.
- The dashboard therefore needs Node **and** bash + jq. Without Node, `/build-fleet:dashboard`
  refuses with a clear message; nothing else is affected.

**Live updates.** Recursive `fs.watch` on `.sdd/` (Node ≥ 20), 200 ms debounce, pushed
to the browser over Server-Sent Events. No polling, no npm packages.

**The linker (display-only).** On each change it rebuilds an index of nodes — spec
sections, ACs, tests, findings, ADRs, approvals, commits — and edges:

| Edge | Source |
|---|---|
| AC → test (covered-by) | TEST_PLAN.md coverage matrix today; spec.md's Acceptance section after 0.11 lite. The linker reads whichever exists. |
| finding → ADR (closed-by) | `disposition: adr ADR-n` |
| ADR → finding (dispositions) | `Dispositions:` in DECISIONS.md |
| finding → refutation | `refuted-by:` |
| ADR → ADR (supersedes) | `Status: superseded by ADR-n` |
| finding → spec place | `ref:` (§3.3) |
| any → id (mentions) | `AC-n`, `ADR-n`, finding ids in prose, commit messages, event `ids` |
| approval → version | the approval hash, resolved against git history |
| backlog item → workspace | the product backlog slug |

Finding state comes from `--report`, never from the linker. A reference to an id that
does not exist (an `ADR-4` that was never written, an AC with no test) is a **broken
link** and is shown, not hidden. Findings with no `ref:` and no id mention go to an
"unanchored" list.

**Pages.** Plain HTML/CSS/JS from `dashboard/`, no build step, works at phone width and
in dark mode.
1. **Project:** backlog (if a product tier exists); the active item with lane, phase,
   tier, risk and a **waiting for approval** banner; every workspace with its state.
2. **Feature / bug:** a lifecycle timeline (phases as bands; gate events as markers,
   green pass, red refuse with reason; approval stamps). Tabs:
   - **Spec** — rendered, with review findings as **margin notes** beside the section
     their `ref:` names, coloured by severity and state.
   - **Traceability** — rows are ACs; columns: spec section, tests, findings, ADRs,
     commits. Gaps highlighted.
   - **Review** — findings by severity and cycle; each opens its **thread** (raised,
     re-raised, refuted or closed by ADR-n).
   - **Decisions** — ADRs with their backlinks.
   - **Events** — the raw log, filterable.
   - **Changes since approval** — for `spec`, a rendered diff between the version the
     latest approval's hash names and the current spec (`.sdd/` content). For `ship`,
     the changed paths and commit subjects since the approved tree, never source
     content (§3.7).

   The **Approve / Send back** panel appears only while a checkpoint is waiting.
3. **Every id is a link:** a chip coloured by state, hover shows the target's one line,
   click jumps to it; each AC, finding and ADR lists **Referenced by**.

No free-form node graph in v1: the matrix and margin notes carry the same information
more legibly past ~30 nodes.

### 3.6 Export (Part B)

`/build-fleet:status --html` runs `server.mjs --export <file>`: one self-contained HTML
file, same renderer and linker, no server, for an auditor, a CI artifact or a PR.

### 3.7 Security (Part B)

**Network and requests.**
- Binds `127.0.0.1` only; no flag binds wider.
- 32-byte random token per run. The first `?t=` visit sets an `HttpOnly; SameSite=Strict`
  cookie and redirects to a token-free URL.
- Host must be `127.0.0.1:<port>` or `localhost:<port>` (DNS rebinding);
  `--allow-host <name>` adds a tunnel hostname.
- Every POST needs a matching `Origin` and an `X-BF-Token` header. The server never
  answers CORS preflights.
- Remote access is documented as Tailscale `serve` or an SSH tunnel; the docs warn
  against anything public.

**Untrusted content.** Every rendered file was written by an agent.
- The markdown renderer (headings, lists, code, emphasis, tables; ~150 lines) escapes all
  text first and emits only allowlisted tags. Raw HTML is never passed through.
- Links: relative or `http(s)` only.
- Response CSP: `default-src 'self'; script-src 'self'; style-src 'self'; frame-ancestors 'none'`.
  No inline scripts, no CDN, no external network calls.
- The export file allows its one inline script by hash in a `<meta>` CSP.
- Each rendered file is capped at 2 MB with a "truncated" notice.

**Server internals.**
- Requests name a slug, never a path; slugs must match `_lib.sh`'s rule. Reads are
  limited to `.sdd/`, `dashboard/`, and git metadata (commit subjects, changed path
  names); diffs are shown only for `.sdd/` files. Source content is never served.
- Scripts run through `execFile`, never a shell. Checkpoint must be `spec` or `ship`;
  the comment goes on stdin, capped at 2,000 characters.
- The page sends the hash it rendered. Server and `approve.sh` both recompute; a
  mismatch returns **409 content changed since you loaded this page**.
- Malformed `EVENTS.jsonl` lines are skipped and counted, never fatal.

**Out of scope:** accounts, more than one approver, HTTPS on localhost, any hosted or
multi-user deployment.

## 4. Compatibility and release

**Part A (0.12.0).**
- New committed files appear in every project's `.sdd/` (`EVENTS.jsonl`). Logging is on
  by default; it records refusals and gate outcomes only.
- New schema `build-fleet/event@1`. `status-snapshot@1` gains `awaiting_approval`
  (additive).
- `ref:` is optional; existing REVIEW.md files are unchanged.
- **CLAUDE.md** "Hooks fail closed" gains the logging exception (§3.1).
- Release checklist: version, marketplace, CHANGELOG (with Compatibility line), README
  counts (hook scripts +1 `record-phase.sh`; scripts +1 `approval-check.sh`), the
  descriptions of architect, qa and reviewer (rubric mirror body change),
  `skills/sdd-protocol/SKILL.md` (EVENTS files, `config.md`, checkpoints, `ref:`).

**Part B (0.13.0).**
- New command `/build-fleet:dashboard` (commands 23 → 24); new script `approve.sh`;
  new `dashboard/` directory; new `docs/dashboard.md` (tunnels, security model, the
  tripwire statement).
- Existing projects add `.dashboard.json` to `.sdd/.gitignore`; the scaffolder writes it
  only for new `.gitignore` files, and `/build-fleet:status` warns while it is missing.
  CHANGELOG Compatibility line.
- product-owner description (send-back input in `/revise`); `commands/fix.md`,
  `commands/ship-fix.md`, `commands/revise.md`, `commands/status.md` updated.
- CI adds Node 20 to the macOS and Linux jobs.

## 5. Testing

**Bash harness** (existing mktemp style; every gate behaviour change gets a failing case
first):
- `log_event` writes the exact `event@1` line; with `EVENTS.jsonl` unwritable or jq
  absent, **every gate's exit code is unchanged**.
- Each hook refusal logs its event; gate scripts log pass and fail; `--report` logs
  nothing and writes nothing.
- `record-phase.sh` logs only on a PHASE change, and fires with `.workflow-in-flight`
  present.
- Agent Write/Edit to `EVENTS.jsonl` is refused.
- `ref:` is ignored by `finalize-gate.sh`, `change-review-gate.sh`,
  `check-review-written.sh`; `rubric-drift.test.sh` passes with the new line in all four
  copies.
- `approval_status`: not-required with no config; awaiting; approved; sent-back; lapsed
  after a content change.
- **Approve → finalize → a source write is allowed** (the STATUS line is outside the
  hash). Same for the bug lane: approve → fix flip → source write allowed.
- `ship` hash ignores `.sdd/` commits after approval; `approve.sh ship` refuses with
  uncommitted source changes.
- Backstops: hand-edited FINALIZED / CONFIRMED with no matching approval still blocks
  source writes.
- `guard-bash-writes.sh` refuses `approve.sh`, `.dashboard.json`, `/api/approve`.
- With no `.sdd/config.md`, the whole existing suite passes unchanged.

**Node** (`node --test`, no dependencies):
- Renderer: XSS corpus — `<script>`, `javascript:` links, raw HTML, attribute
  breakouts, entity tricks.
- Linker: fixture `.sdd/` → expected nodes, edges, broken links, unanchored findings;
  TEST_PLAN shape and spec-Acceptance shape both.
- Server: wrong Host 403; no token 401; missing Origin refused; preflight unanswered;
  path-like slug rejected; stale hash 409; 2 MB cap; SSE event after a file change.

**Smoke** (`docs/v0.5/smoke/smoke.sh`): a run with `REQUIRE_APPROVAL: spec` — gate
refuses `awaiting-approval`, `approve.sh` approves, gate passes, `--export` produces HTML
containing the expected id links.

**CI:** Node 20 on macOS and Linux. Locally `run-tests.sh` skips the Node suites with a
notice when Node is absent; CI always runs them.

**Manual, once:** a browser pass at phone width and in dark mode; one live run on a
scratch project (not production tap).

## 6. Success criteria

- **Audit completeness:** on a test feature taken through spec, review, finalize, build
  and handoff, every gate decision appears in its `EVENTS.jsonl`.
- With no `.sdd/config.md`, gate behaviour is unchanged (existing suite green).
- An approver, through a tunnel on a phone, can see what changed since their last
  approval and approve it; the gate then passes without anyone editing a file.
- Every id in a rendered page links to its target or shows as broken.
- No external network calls; no npm dependencies.

## 7. Out of scope

- **Live session control** (layer 3): send-back that starts rework, remote tool approval.
  Waits for channels to leave research preview; a later 1.x release.
- A dashboard that starts and runs agents (the Vibe Kanban model).
- A multi-project view; multiple approvers; verified identity; signing keys.
- Token and cost per step beyond the existing `LAST_REVIEW_OUTPUT_TOKENS`.
- Writing send-back comments into REVIEW.md as findings.
