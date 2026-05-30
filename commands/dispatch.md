---
description: Classify a feature request as trivial / standard / large; returns the M4 routing verdict without modifying any state. Inspectable lane preview before committing to /build-fleet:new-feature.
argument-hint: "<feature description>"
allowed-tools: Read, Task
---

# /build-fleet:dispatch

You are the **orchestrator**. The runtime rulebook is the `sdd-protocol` skill. This command is the v0.2 M4 query interface to the `classifier` subagent: given a feature description, it returns the routing verdict (`trivial` / `standard` / `large`) without touching `.sdd/` state. Use it to preview the lane before invoking `/build-fleet:new-feature`, or to sanity-check a classification mid-flight.

## What this is NOT

This command does NOT:
- Create or modify `.sdd/`. It is read-only.
- Scaffold a feature workspace.
- Set TIER or BUILD_MODE on any feature.
- Run the SDD pipeline.

For routing-and-scaffolding, use `/build-fleet:new-feature <slug>` after settling on a description. That command invokes the classifier internally and writes the verdict to PROGRESS.md.

## What you do

1. **Validate arguments.** `$ARGUMENTS` is the feature description. If empty, refuse with `BUILD_FLEET_REFUSE: dispatch requires a feature description in arguments` and exit 2.

2. **Invoke the classifier.** Use the Task tool to spawn `build-fleet:classifier` with this prompt:

   > Classify the following feature request per agents/classifier.md. Emit a single JSON verdict and stop.
   >
   > Feature description: `$ARGUMENTS`
   >
   > Project context: read whatever files in the current directory help you size the work. Do not exhaustively read source.

3. **Parse the verdict.** The classifier emits a single JSON block of the shape documented in agents/classifier.md (`tier`, `rationale`, `skip_review`, `build_mode`, `skeleton_spec_hint`, `confidence`). Extract it.

4. **Emit the classification signal.** Before any human-readable output, write exactly one line:

   ```
   BUILD_FLEET_CLASSIFICATION: {"tier":"<...>","build_mode":"<...>","skip_review":<bool>,"confidence":"<...>"}
   ```

5. **Report to the user.** Human-readable summary:
   - Tier with one-line rationale.
   - Confidence level.
   - Routing implications:
     - `trivial`: `/build-fleet:new-feature <slug>` will scaffold a skeleton spec via PO (using the classifier's `skeleton_spec_hint`); user can run `/build-fleet:finalize` immediately to skip REVIEW.
     - `standard`: `/build-fleet:new-feature <slug>` will scaffold and PO will draft the full spec; user runs `/build-fleet:review` then `/build-fleet:finalize` as the v0.1 flow.
     - `large`: same as standard PLUS PROGRESS.md gets `BUILD_MODE=deep-build` so finalize routes the implementation phase to `workflows/deep-build.js`.
   - If `confidence=low`: surface the rationale and recommend the user either provide a more detailed description or override the tier manually by editing PROGRESS.md after scaffolding.

6. **Cleanup.** No state to clean — this command never wrote any.

## Exit codes

| Exit | Meaning |
|---|---|
| 0 | Classification emitted successfully |
| 1 | Classifier subagent errored or returned an unparseable verdict |
| 2 | Missing or invalid arguments |

## Refusal contract

All refusals begin with `BUILD_FLEET_REFUSE: ` for orchestrator consumption.

## Examples

```
/build-fleet:dispatch "fix typo in README"
→ BUILD_FLEET_CLASSIFICATION: {"tier":"trivial","build_mode":"standard","skip_review":true,"confidence":"high"}

/build-fleet:dispatch "add --shout flag to greet CLI"
→ BUILD_FLEET_CLASSIFICATION: {"tier":"standard","build_mode":"standard","skip_review":false,"confidence":"high"}

/build-fleet:dispatch "rewrite greet to support multiple languages with i18n loader and locale dispatch across cli, core, and api packages"
→ BUILD_FLEET_CLASSIFICATION: {"tier":"large","build_mode":"deep-build","skip_review":false,"confidence":"high"}
```
