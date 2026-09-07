# 0040. The soak is declared in git and judged from git's dates

- **Status:** accepted
- **Date:** 2026-09-07
- **Deciders:** blairforce1, with Claude Code
- **Supersedes:** none

## Context

Every ascent on the ladder rests on a soak: the rung above ran the artifact for a while, cleanly, and that is the evidence prod receives it on. The length of that while lived in one place, `slo-gate`'s minimum residency, as an environment variable defaulting to two minutes, and nowhere for charts or Kubernetes minors. Stage 16 promotes prod onto dev's minor on dev's soak and had no number to hold it to; a soak that lives in people's heads is a feeling, and the day it is shortened nobody can say by whom.

## Decision

`soak.yaml` at the repo root, beside the freeze calendar, declares the soak per artifact kind (image, chart, kubernetes) and target rung (dev, prod), two numbers each: `min`, what the artifact owes on the rung above before it climbs, and `max`, how long the rung below may lag behind it before the rung above is testing against a platform the rung below does not run. Entry rungs declare nothing: a pin owes no soak. `scripts/soak-gate` holds every promotion pointer a change moves to the declared length, and reads the time served from git's own dates: the first-parent commits that put the candidate on the rung above and kept it there, never a clock somebody started. A candidate the rung above is not serving is a FAIL, so a skipped rung cannot pass as a soak. The gate runs in the pre-push hook, in CI's `pr-record` job and in the `promote` skill; `slo-gate` takes its minimum residency from the same file. `max` is judged where there is no PR to refuse: `check-ladder-due` (the gate's `--due` mode, run by `./scripts/check` through its prefix) prints one line per ascent in progress, SOAKING below `min`, DUE between the two, FAIL past `max`, FROZEN when an active freeze covers the rung's paths. With `--items` it opens one work item per due ascent that has none, a sub-issue of the standing item that owns the artifact class, closed by the promotion PR's `Closes:`. A decision not to promote a candidate is the same item closed with the reason: the report reads a closed item with the ascent's title as HELD, green, until the rung above serves something else, and never opens another for it. The report is the operating loop outside a stage: it runs at every stage start in the course and on a daily schedule on a fleet (stage 27 wires the schedule beside the calendar), and a due line is an item with an owner rather than a line nobody actions. A `Soak-waived: <reason>` trailer passes a failing verdict, loudly and in the record, in the shape of the freeze calendar's override. The course's values are short enough to run in a sitting; a fleet raises them.

## Considered options

- **The soak as an environment variable.** Where it was; unversioned, unreviewed, per kind only where somebody remembered.
- **A warning instead of a gate.** A warning nobody acts on is the thing rule 5.9 was written against.
- **A gate with no waiver.** An incident then bypasses the check by turning it off, and the record shows nothing.
- **Durations in `clusters/versions.yaml`.** A different lifecycle: versions are pins that move by promotion, the soak is policy that moves by review.
- **A minimum alone.** It stops a promotion coming too early and says nothing about one that never comes; the rungs drift apart in time and the evidence stops being about prod without any gate noticing.
- **The report opening items on its own.** A gate that writes is not a gate (rule 5.9); the write is an explicit flag, the way `derive-ladder --write` is, and the schedule runs both.

## Consequences

- Easier: one number per ascent, reviewed like any other change, and read back by `soak-gate --declared`.
- Easier: the gate's evidence is the same history the audit reads, so "how long did it soak" has the same answer at the PR and a year later.
- Harder: the course's values are minutes to days, and a reader must raise them for a fleet; `appendices/take-it-to-production.md` says to what.
- Follow-up: the daily schedule and its posting on the standing item land at stage 27 with the calendar; until then `./scripts/check` at each stage start is the schedule.
- Follow-up: stage 13's chart pins carry `pin` at every rung; the gate judges a chart ascent from the diff regardless of subject type, and the subject vocabulary is not changed here.

## Where it is taught or enforced

Rule 5.7; stage 16 (declared and first judged); `scripts/soak-gate`, `scripts/check-ladder-due`, `soak.yaml`, `hooks/pre-push`, CI's `pr-record` job, the `promote` skill, `scripts/slo-gate`.
