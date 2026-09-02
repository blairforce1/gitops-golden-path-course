---
name: run-drill
argument-hint: "[rebuild <act> | break <stamp> | breach | break-glass | insider | stale | region] [--yes]"
description: >-
  Run a rebuild drill or a game day (a scripted act drill, a breach rotation, a break-glass, an insider attack on the controls, a stale fleet, a region rebuild) against machinery that already exists, capture the numbers from artifacts, and write the evidence pack on the drill's work item. Use when asked to prove the fleet rebuilds, to run a game day, or to run the quarterly recovery test.
---

# run-drill

A drill builds nothing new. It throws a scenario at what exists and produces evidence: numbers from artifacts, refusals collected, findings filed as PRs.

## 1. Preconditions

- The drill's work item exists: an act's rebuild drill is the act checkpoint's own item (the one its PRs already cite); an ad-hoc game day gets a new one, labelled `drill` and, for incident drills, a severity. Every PR the drill opens cites it.
- The fleet is green before the drill starts: `./scripts/check` for the toolchain, the relevant checkpoint script for cluster state. A drill on a red fleet measures the wrong thing.
- State the definition of "nothing" for this drill in the item's first comment: what is destroyed, what survives and why (git, the root keys, the cloud resources, the region).
- Destructive drills demand the explicit flag (`--yes`) and print the blast radius when run bare. Where a drill costs money, print the estimate first.

## 2. The scenarios

| Drill | What it attacks | Injected by |
|---|---|---|
| rebuild (`scripts/act-N-drill`) | the claim that the fleet is derivable from git | the script: down, up, sync, pay the era's IOUs, checkpoint |
| break and restore | detection and attribution | a `break(<stamp>): ` commit by PR; restore by `pr-revert` |
| breach rotation | key custody | the `rotate-secret` skill's leak path, all at once, under time |
| break-glass | the change machinery itself | the `break-glass` skill, on a stuck check or a dark forge |
| insider | the controls | a direct push, a prose title, a closed work item, an off-ladder `base/` edit, a freeze crossing; the deliverable is the list of refusals; anything that lands is a finding |
| stale fleet | currency | a month untouched; catching up is the queued dependency PRs and one rung climbed, the parity gates naming the drift |
| region rebuild | the platform substrate | the region comes back elsewhere; identity re-federates; RPO and RTO from artifacts |

Every injection is a PR with human hands on the merge; never `kubectl`.

## 3. Watch, then measure

Say what to expect and when before the break (nothing for an interval, then one row leaves Ready while the rest stay green; a cascade for one scrape on every push). Then measure from artifacts only:

```sh
./scripts/rung-time <sha> <context> <ctx> <stamp>       # how fast a good change lands
./scripts/detect-time <stamp> <ctx> '<break subject>'    # how fast a bad one surfaces, both numbers
```

Rebuild time is the span between the rebuild's first artifact and the checkpoint's PASS, read from timestamps, not a clock.

## 4. The pack

On the work item: the scenario as stated, the numbers with their sources, one `audit-evidence` dossier per injected change, the refusals (verbatim gate output), the findings, and the PRs opened as a result. A drill that finds nothing wrong says so, with the refusals as the proof. A person closes the item.

## Rules

- A rebuild runs for minutes (nine on a three-cluster kind fleet) and a tool timeout would cut it mid-destruction. Run the script detached with its output in a log, then poll the log until its results line: `nohup ./scripts/act-N-drill --yes > /tmp/act-N-drill.log 2>&1 &` and `tail -n 5 /tmp/act-N-drill.log` every minute or so. Never run it as a foreground command with a timeout shorter than the drill.
- Attack what exists; build nothing during a drill.
- No stopwatch.
- The drill's PRs cite the drill's work item.
- The pack closes the drill. What the checkpoint does next is the reader's to know, not the skill's to prescribe: when the rebuild runs last, the other drills are already in the record.
- Separate findings about the platform from findings about the drill's own script; both are PRs in this repo. A finding about the course (its text, a seeded script's logic) is reported on the work item with the evidence, not applied: the course repo is not this skill's to change, and a seeded script is changed course-first by its author and then synced.
