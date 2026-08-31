# 0017. Automation writes only at its ladder's entry rung; robots propose, gates judge, humans merge above it

- **Status:** accepted
- **Date:** 2026-08-19
- **Deciders:** blairforce1, with Claude Code
- **Supersedes:** none

## Context

Image update automation and dependency bots can write to any overlay they are pointed at, and wiring one at prod "to save the PR step" is a common shortcut. Doing so deletes the ladder rather than automating it: the version no longer climbs against evidence, it just arrives everywhere. The platform has two ladders with two entry points: app images enter at dev, platform changes (charts, controllers, Kubernetes minors) enter at platform. The platform cluster runs the dev overlay, so it receives app bumps transitively at the same instant dev does, which is enough for its job of validating platform changes against a representative workload.

## Decision

New versions *enter* the ladder automatically and *climb* it only by reviewed PR. Each robot writes at its own ladder's entry rung and nowhere else: image automation at the dev overlay (edit surface scoped by setter markers, which prod has none of), Renovate at the platform overlay for charts and the base image. Above the entry rung, the pattern is robot proposes, gates judge, human merges at the exposed end: a scheduled workflow opens the wave or ascent PR when the soak clock expires, the soak, SLO and channel gates carry every success metric as required checks, and a human merges. Automation depth is a per-channel dial: engineering and internal waves may earn auto-merge on green gates; GA waves stay human-merged. The robot has exactly the human's dev privilege: it commits to a branch, its PR is opened with the repository token, and auto-merge waits on the same required checks a human waits for.

## Considered options

- **Automation at every rung.** The ladder becomes decoration.
- **A platform-specific app pin so platform sees releases first.** Symmetry at the cost of a third pin per release with nobody whose job is to read it; platform's "tests next" role belongs to its own ladder.
- **Renovate as the wave vehicle.** Renovate answers "does an upstream datasource have something newer"; a wave's upstream is the repo's own faster channel plus a clock plus metrics, and a custom datasource over raw files fights the tool.
- **A robot bypass on the ruleset.** Rejected in [0002](0002-protection-on-main-from-day-zero.md).

## Consequences

- Easier: a production freeze needs only a merge-time gate, because prod has exactly one write path and no automation to suspend ([0023](0023-change-freeze-is-a-calendar-in-git.md)); metrics never live in the robot, so they cannot be gamed by editing it.
- Harder: the robot's branch raises no `pull_request` event when the PR is opened with the repository token, so the CI workflow keeps a `push` trigger on that branch and the record check judges the landed commit.
- Harder: the risk relocates to someone weakening the invariant to save a step, which is a commit under `clusters/` or the workflow files, which code owners protect ([0024](0024-codeowners-by-effective-blast-radius.md)).
- Follow-up: Renovate runs on the config repo and Dependabot on the app repo's Dockerfile and Actions pins, where the two cannot meet ([0034](0034-renovate-not-dependabot-for-the-config-repo.md)).

## Where it is taught or enforced

Rule 5.4 (entry is automatic, ascent is not); stage 13 (platform promotion, Renovate), stage 14 (image automation, the robot's PR), stages 28–29 (wave automation); `scripts/freeze-gate`, `scripts/slo-gate`, `channel-gate`.
