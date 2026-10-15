# build-fleet

A spec-driven software house for Claude Code. You describe a feature; a fleet of
role agents writes the spec, attacks it in review, builds it tests-first, reviews
the change and hands it off. Hooks enforce every phase gate: no source is written
before the spec is approved, and nothing ships until the tests pass and the change
is reviewed.

You need five commands.

## Requirements

- **Claude Code v2.1.154 or later**, with the **dynamic workflows** feature
  enabled (`/config` → "Dynamic workflows" on Pro plans; on by default for
  Max / Team / Enterprise). build-fleet has a **hard** dependency on the
  `Workflow` tool — REVIEW, PLAN_REVIEW, and deep-build run as dynamic workflows,
  with no command-pipeline fallback. If the runtime is missing, the affected
  command refuses with a `BUILD_FLEET_REFUSE:` line carrying
  `{"code": 3, "reason": "workflow-runtime-unavailable"}` (the signal lines are
  the machine contract — commands cannot set process exit codes).
- For **headless** callers, `Workflow` must be in the session's allowed tools,
  e.g. `claude -p --allowedTools "Workflow,Read,Edit,Write,Bash,Agent,Task" …`.
- **`jq`** — required by every gate hook and by `scripts/status-snapshot.sh`
  (`brew install jq` / `apt install jq`).
- **`bash`** — all hooks are bash scripts. On Windows this means **Git Bash or
  WSL**; without bash the gate layer silently does not run.
- **`git`** — the target repo must be a git repository (gates, counterfactual
  verification, and the bug lane all assume it).

**Release channel.** `main` always equals the latest tag — installing from
`main` installs the latest release.

---

## Install

The plugin is distributed from a GitHub repository as its own single-plugin
marketplace.

```
/plugin marketplace add https://github.com/rocar/build-fleet.git
/plugin install build-fleet
```

Then verify the fleet loaded — `/agents` should list all eight `build-fleet:*`
agents.

**Transport note.** The `owner/repo` shorthand (`/plugin marketplace add
rocar/build-fleet`) resolves to **SSH** (`git@github.com:…`). On a machine
without a GitHub SSH key configured it will fail with a publickey error — use
the full **HTTPS** URL shown above instead, or a local path during development.
If the repo is **private**, the same credential (SSH key or HTTPS token via
`gh auth`) must be able to read it.

For local development, point Claude Code at a working copy directly:

```
claude --plugin-dir /path/to/build-fleet
```

### Updating

The plugin cache is **keyed by version** (`.claude-plugin/plugin.json`'s
`version`). `/reload-plugins` only re-reads the *local* cache — it does **not**
re-fetch from GitHub. To pull a new release you must update the marketplace clone
and reinstall:

```
/plugin marketplace update build-fleet   # re-fetches the repo
/plugin update build-fleet               # installs the new version into a fresh cache
/reload-plugins
```

A version bump is required for the cache to refresh; same-version pushes won't
take effect on an installed instance.

### The target repo's CLAUDE.md

Check it before the first run. `CLAUDE.md` outranks skills in instruction
precedence, but the gate hooks enforce the protocol regardless — so a generic
directive that contradicts `sdd-protocol` ("write the plan to `tasks/todo.md`",
"given a bug, just fix it") does not win. It produces an agent that confidently
attempts a blocked action and burns a cycle on an exit-2. The file is also injected
into every dispatched role agent, so a line written for the orchestrator is read by
the coder too.

**[`docs/CLAUDE.sample.md`](docs/CLAUDE.sample.md)** is a copyable starting point: the
common conflicts and what each one actually hits, plus a fleet-native body covering
entry-point routing, the one-item-in-flight rule, `.sdd/` commit policy, and per-role
write lanes. It reserves the product-memory marker region so ratification splices in
place rather than appending at EOF.

---

## 60 seconds

```
/build-fleet:start add CSV export to the report page
```

`start` scaffolds the feature, asks you what it needs to know, drafts the spec,
and runs the review → revise loop until the spec is clean. It stops and tells you
the spec is ready.

```
/build-fleet:build
```

Running `build` is your approval of the spec. qa writes the failing tests, coder
makes them pass. It stops when the build is done.

```
/build-fleet:ship
```

`ship` reviews the change, has coder fix what the review finds, and hands off to
devops, which ships or refuses.

Every run ends with one line saying why it stopped and what to run next:
`BUILD_FLEET_LITE_DONE: {"stop":"spec-ready","next":"/build-fleet:build"}`.
Running a command again resumes where it stopped.

**Got a plan for a whole product?** `/build-fleet:start --product "<vision>"`
drafts a vision, a phased backlog and a stack, reviews them, and stops for you to
ratify. After that, `/build-fleet:start` with no idea picks up the next backlog
feature.

## Got a bug?

```
/build-fleet:fix the export drops the last row
```

`fix` files the bug, writes a failing reproduction, proposes a root cause and has
it challenged, applies and verifies the fix, and hands off to devops.

## Where am I?

```
/build-fleet:status
```

What is in flight, what review found, and the next command. `status` is also where
you make the decisions only a human makes:

| Command | Does |
|---|---|
| `/build-fleet:status park <reason>` | Shelves the item in flight, so another can start. |
| `/build-fleet:status resolve <decision>` | Unblocks an escalation with your recorded decision. |
| `/build-fleet:status ratify [force]` | Ratifies the product plan. |

`build`, `ship` and `status` can only be typed by you; Claude cannot run them. It
can still run `start` and `fix` for you, and `fix` takes a bug all the way to devops.
The steps behind `build` and `ship` are not locked against Claude yet, so ask it to
stop at the spec if you want to be the one who approves.

## What the gates guarantee

- No source file is written until the spec is approved (bugs: until the diagnosis
  is confirmed and a reproducing test exists).
- The spec cannot be approved while review leaves a blocker or an unanswered major
  open.
- Shell commands are not a way around the write gates.
- Every gate fails closed: an unexpected state blocks rather than allows.
- Every acceptance criterion maps to a named test that exists, checked before and
  after the build and at ship. Run the same check in your CI:

  ```bash
  bash <path-to-build-fleet>/scripts/drift-gate.sh --all   # exit 2 on drift
  ```

The full hook table, the state machine, the product tier, headless use and the
hidden steps are in **[docs/reference.md](docs/reference.md)**. The headless
contract is [docs/v0.2/CONTRACT.md](docs/v0.2/CONTRACT.md).

## Development

```bash
bash scripts/run-tests.sh
```

Runs every hook and script suite plus the bug-lane smoke test; CI runs it on
macOS (bash 3.2) and Linux. Conventions are in [docs/reference.md](docs/reference.md#development).

## License

MIT — see [LICENSE](LICENSE).
