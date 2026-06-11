---
description: Preview a feature's tier classification; writes no state
argument-hint: "<feature description>"
allowed-tools: Read, Task
---

# /build-fleet:dispatch

You are the **orchestrator**. The runtime rulebook is the `sdd-protocol` skill. This command is the read-only query interface to the `classifier` subagent: given a feature description, it returns the routing verdict (`trivial` / `standard` / `large`) without touching `.sdd/` state. Use it to preview the lane before invoking `/build-fleet:new-feature`, or to sanity-check a classification mid-flight.

## What this is NOT

This command does NOT:
- Create or modify `.sdd/`. It is read-only.
- Scaffold a feature workspace.
- Set TIER or BUILD_MODE on any feature.
- Run the SDD pipeline.

For routing-and-scaffolding, use `/build-fleet:new-feature <slug>` after settling on a description. That command invokes the classifier internally and writes the verdict to PROGRESS.md.

## What you do

1. **Validate arguments.** `$ARGUMENTS` is the feature description. If empty, refuse with `BUILD_FLEET_REFUSE: {"command":"dispatch","code":2,"reason":"missing-description"}`.

2. **Invoke the classifier.** First, if `.sdd/_product/STACK.md` exists, read its
   binding stack (everything not marked `PROVISIONAL`) so the classifier derives the
   skill manifest from the product stack — mirroring `/build-fleet:new-feature` step 5b
   so this preview matches what scaffolding would actually emit. Then spawn
   `build-fleet:classifier` via the Task tool with this prompt:

   > Classify the following feature request per agents/classifier.md. Emit a single JSON verdict and stop.
   >
   > Feature description: `$ARGUMENTS`
   >
   > Inherited product stack (only if a product tier exists): <paste the binding stack
   > from .sdd/_product/STACK.md, or "none — no product tier">. Use it to derive
   > `feature_type` and the skill manifest; do not let it change sizing.
   >
   > Project context: read whatever files in the current directory help you size the work. Do not exhaustively read source.

3. **Parse the verdict.** The classifier emits a single JSON block of the shape documented in agents/classifier.md (`tier`, `rationale`, `skip_review`, `build_mode`, `skeleton_spec_hint`, `confidence`, `skill_manifest`). Extract it. `skill_manifest` may be `null`.

4. **Emit the classification signal.** Before any human-readable output, write exactly one line:

   ```
   BUILD_FLEET_CLASSIFICATION: {"tier":"<...>","build_mode":"<...>","skip_review":<bool>,"confidence":"<...>"}
   ```

   If `skill_manifest` is non-null with at least one non-empty `roles` entry, also emit (preview only — dispatch writes no file):

   ```
   BUILD_FLEET_SKILL_MANIFEST: {"feature_type":"<...>","coder_skills":[...],"qa_skills":[...]}
   ```

5. **Report to the user.** Human-readable summary:
   - Tier with one-line rationale.
   - Confidence level.
   - Routing implications:
     - `trivial`: `/build-fleet:new-feature <slug>` will scaffold a skeleton spec via PO (using the classifier's `skeleton_spec_hint`); user can run `/build-fleet:finalize` immediately to skip REVIEW (then `/build-fleet:build`).
     - `standard`: `/build-fleet:new-feature <slug>` will scaffold and PO will draft the full spec; user runs `/build-fleet:review`, `/build-fleet:finalize`, then `/build-fleet:build`.
     - `large`: same as standard PLUS PROGRESS.md gets `BUILD_MODE=deep-build` so `/build-fleet:build` routes the implementation phase to `workflows/deep-build.js`.
   - If `confidence=low`: surface the rationale and recommend the user either provide a more detailed description or override the tier manually by editing PROGRESS.md after scaffolding.
   - **Skill routing preview.** If `skill_manifest` is non-null, show
     `feature_type` and the per-role skill names (coder / qa) it would write to
     `.sdd/<slug>/SKILL_MANIFEST.md` at `/build-fleet:new-feature` time. Note these
     are **generic, advisory** names per the `skill-routing` skill — a name only
     takes effect at BUILD if a skill of that name is available, else it's a no-op.
     If `skill_manifest` is `null`, state that no domain routing applies.

6. **Cleanup.** No state to clean — this command never wrote any.

## Refusal contract (machine-readable)

A slash command runs inside the model session and **cannot set a process exit
code** — the session exits 0 either way. The `BUILD_FLEET_*` signal lines on
stdout are the **sole machine contract**: `BUILD_FLEET_CLASSIFICATION` =
success; `BUILD_FLEET_REFUSE` = refused, its JSON carrying `"code"` (an integer
preserving the legacy exit-code semantics: `2` = missing/invalid arguments,
`1` = classifier errored or returned an unparseable verdict) and `"reason"`
(a kebab-case slug — e.g. `missing-description`, `classifier-unparseable`).
Orchestrators dispatch on the signal line, never on the process exit status.

## Examples

```
/build-fleet:dispatch "fix typo in README"
→ BUILD_FLEET_CLASSIFICATION: {"tier":"trivial","build_mode":"standard","skip_review":true,"confidence":"high"}

/build-fleet:dispatch "add --shout flag to greet CLI"
→ BUILD_FLEET_CLASSIFICATION: {"tier":"standard","build_mode":"standard","skip_review":false,"confidence":"high"}

/build-fleet:dispatch "rewrite greet to support multiple languages with i18n loader and locale dispatch across cli, core, and api packages"
→ BUILD_FLEET_CLASSIFICATION: {"tier":"large","build_mode":"deep-build","skip_review":false,"confidence":"high"}
```
