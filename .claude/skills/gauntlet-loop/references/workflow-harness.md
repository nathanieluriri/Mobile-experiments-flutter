# Running the gauntlet as a Workflow

Only use the Workflow tool when the user has opted into workflows. Load the
`workflow-authoring` skill before writing the script.

## When a workflow pays off

| Situation | Use |
| --- | --- |
| 1 to 3 parts, want to see each verdict, decomposition may change | `Agent` tool, inline |
| 4+ parts, many items, loop-until-dry, 20+ rounds to drive | Workflow |
| Most real work | Hybrid: scout and settle the parts inline, then hand the settled list to a workflow |

## Script rules

- Pass the verdict schema from `critic-brief.md` as `schema` on each critic `agent()` call, so
  a malformed verdict is retried at the tool layer instead of silently misparsed.
- `agent()` can return `null`. Treat `null` as FAIL (or retry once), never as PASS. An
  unhandled null reads as a passing part.
- No `Date.now()` or `Math.random()`; they throw. Put the wall-clock ceiling in `args` and
  let the orchestrator enforce it between runs.
- Bound the loop per part with a fixed round count from `args`, never `while (true)`.
- Every critic is a new `agent()` call with its own prompt; never reuse one.
- Return a per-part summary (verdict, round, standing issues, checks added) so the
  orchestrator can write `GAUNTLET.md` and report.

## Resuming

- `resumeFromRunId` replays the unchanged prefix of agent calls from cache and re-runs from
  the first edited call. Same script and same args is a full cache hit.
- Before diagnosing an odd result, read the run's `journal.jsonl`: it records what each agent
  actually returned.
- `GAUNTLET.md` remains the source of truth across sessions; update it from the workflow's
  return value.
