---
name: gauntlet-loop
description: Run an autonomous build, adversarial critique, improve loop that keeps iterating until the work clears a named real-world quality bar, judged by fresh, blind critic agents that must reproduce every issue they raise. Use this whenever the user says "gauntlet", "run it through the gauntlet", or asks for work that should be harshly critiqued by independent agents and improved until it passes, and also when they say things like "make this actually good, not just working", "keep iterating until it's production quality", "tear this apart and fix it", "iterate on this without me babysitting it", "polish this until it's great", or "I want this to beat Linear" (or any named product). Prefer it over a plain build-test-fix loop when quality against a real benchmark is the goal rather than mere correctness. Do not use it for quick fixes, single bug reports, one-off code reviews, or questions.
---

# Gauntlet loop

A normal loop stops when nothing is broken. The gauntlet stops when the work **beats a
named real thing**, as judged by critics who never saw the builder's reasoning and who
must reproduce every flaw they report. You trade tokens for the user's attention, so keep
that trade honest: bound it, right-size it, and report back straight.

## 1. Settle the contract before building anything

Reply to the user with exactly these four lines, then proceed unless they veto:

```
Goal:      <what exists at the end, one sentence>
Bar:       <a named, concrete real-world benchmark, e.g. "empty states as tight as Linear's">
Budget:    <rounds per part (default 3)> rounds, <wall-clock ceiling>, ~<N> agents total
Evidence:  <how critics will exercise it: tests, launch + screenshot, run the CLI, read end to end>
```

- **The bar is the highest-leverage decision in the run.** "Good", "clean" and
  "production quality" are not bars. Pick a real product, spec, or standard. See
  `references/reference-bars.md` for defaults per domain. Fix the bar now so it cannot
  drift to match whatever gets built.
- **Evidence means exercising the thing.** A critic that only reads source is guessing.
  For this repo that usually means `flutter analyze`, `flutter test`, golden tests, or
  launching the app and taking screenshots.
- If the user already gave a bar and budget, use theirs.

## 2. Decompose

Split the work into 3 to 6 parts that can each be judged on their own, each owning a
disjoint set of files where possible. A single small artifact is one part; do not invent
structure. Write the parts into the ledger (section 8) before round 1.

## 3. The loop, per part

```
round r:
  builder    -> produces or improves the artifact (round 1: build; later: fix the verdict's issues)
  inspector  -> only if evidence must be produced (screenshots, perf traces); else skip
  critic     -> a FRESH Agent call, blind, returns a structured verdict
  verdict    -> PASS: part is done, stop spending on it
                FAIL: issues go to the next builder round, each becomes a durable check
```

Rules that make it work (do not weaken any of them):

- **Blind critic.** Give the critic the spec, the bar, the artifact, and the evidence. Never
  the builder's summary, commit message, or reasoning. Narrative creates pressure to endorse.
- **Fresh critic every round.** A new `Agent` call, never `SendMessage` to a previous critic.
  A reused critic anchors on its own old list.
- **Reproduction required.** Every issue needs steps to see it. No steps, no issue. This is
  what stops fabricated flaws.
- **Explicit permission to pass.** Tell the critic: if you exercised it and cannot name a
  concrete shortfall against the bar, PASS is the correct answer. Never ask for "at least N
  problems".
- **Distinct lenses, not clones.** Add a second or third critic only when a part can fail in
  unrelated ways, and give each a different job (correctness, bar comparison, hostile user,
  performance, accessibility). Clones find the same things.
- **Synchronous spawns inside the loop.** Run builder and critic agents in the foreground
  (`run_in_background: false`). The orchestrator owns control flow. A backgrounded builder
  plus an ended turn means nothing re-enters the loop, the child may be unable to report
  back, and it can outlive the parent and keep spending. Background is only for work that is
  outside the loop.

Read `references/critic-brief.md` before spawning your first critic. It has the brief
template and the verdict schema.

## 4. Durable checks

Every confirmed, reproducible finding becomes a permanent check before the part can pass:
a test, an assertion, a golden, a lint rule, or a checklist line in the ledger. Otherwise
round N+1 rediscovers round N's bug. The next builder round must add the check and the fix
together.

## 5. Integration gauntlet

Parts passing does not mean the whole passes. After every part is PASS, run one more fresh
critic over the integrated result against the same bar, with the same evidence rule. Seam
issues go back to the owning part.

## 6. Convergence: when to stop

| Signal | Meaning | Action |
| --- | --- | --- |
| Budget or clock hit, no PASS | Not converging | Stop. Report standing issues and your read on why |
| Same issue survives two rounds | Builder cannot fix it from this framing | Reframe the issue or fix the decomposition; a stuck issue often sits on a badly placed seam |
| Issue count flat while the artifact keeps changing | Critic is finding equivalent nits | The bar is reached. Call PASS and move on |
| A passing part starts failing | Regression | Fix now and add a durable check |
| Two rounds of "the bar does not fit" | Wrong bar | Stop and renegotiate the bar with the user. Their call, not yours |

When the clock runs out mid-round, close the ledger in its current state and report. Do not
squeeze in one more fix.

## 7. Right-size the machinery

- No inspector unless evidence needs producing. No screenshot agent for a CLI tool, no
  server for a file the critic can open directly.
- Kill parts that pass. Re-critiquing a passing part "to be sure" is how costs double.
- Worktree isolation only when parts would really collide on files.
- 1 to 3 parts where you want to see each verdict: drive it inline with the `Agent` tool.
  4+ parts or long loop-until-dry runs: use the Workflow tool only if the user has opted into
  workflows; otherwise stay inline and say a workflow could speed it up. Read
  `references/workflow-harness.md` before writing a workflow script.

## 8. The ledger: GAUNTLET.md

Create `GAUNTLET.md` at the work root from `assets/GAUNTLET.template.md` before round 1 and
update it at the end of every round, before the next begins. A run killed at any moment must
leave resumable state. On start, if a `GAUNTLET.md` already exists, read it and resume from
it instead of restarting. It is local working state, not a deliverable (this repo gitignores
it).

## 9. Reporting back

End with a straight account, short:

- Outcome per part: PASS in round r, or FAIL with the standing issues.
- What the critics kept catching (the most useful signal of the run).
- Durable checks added.
- Budget used against the budget set.
- Anything you chose not to fix and why, and any bar you think was wrong.

Never call a part passing that a critic did not pass. If you stopped early, say so first.
