# 0024. Code owners follow effective blast radius, paired with the rendered diff

- **Status:** accepted
- **Date:** 2026-08-24
- **Deciders:** blairforce1, with Claude Code
- **Supersedes:** none

## Context

A shared source means every cluster reconciles every commit, but only the clusters whose render differs apply anything. So the ladder only gates what lives on a rung: a pin under `apps/overlays/prod/` reaches one cluster, while the same one-line edit under `apps/base/` reaches all three at once with no promotion. The folder layout describes a promotion boundary that nothing enforces. Locking `/clusters/prod/**` while leaving `base/` writable is the classic blind spot, and CODEOWNERS has two more: last-matching-pattern-wins semantics (the inverse of `.gitignore`), and the branch-protection toggle that silently stops requiring owner review.

## Decision

Protection follows effective blast radius, not folder names. The paths that need their own reviewers are named with the reason: `apps/base/` (fans out to every cluster), `apps/overlays/prod/` (the rung the ladder exists to protect), `clusters/` (changes what a cluster is), `infrastructure/` (every workload's blast radius), `.sops.yaml` and `secrets/` (the access list), `policy/` and `.github/workflows/` (the gates: weakening a check should be harder to merge than failing it). `CODEOWNERS` is the map, the ruleset's `require-owners` is the requirement, and `path-gate` is the plan-independent report that names which protected group a change touches and why. The dev overlay is deliberately unprotected: gating the entry rung deletes the reason it exists. Owners are teams, never personal emails. The pair is the rendered diff on the PR ([0009](0009-identifier-alignment-one-string-seven-homes.md) makes it legible): blast radius shows what a change reaches, owners ensure the right person is looking. CODEOWNERS gates merge, not apply; it pairs with, never replaces, cluster-side enforcement.

## Considered options

- **Protect `clusters/prod/` only.** The blind spot.
- **Protect everything.** Deletes the entry rung's speed and turns review into theatre.
- **Repo per team.** Folder-scoped ownership delivers most of the isolation people split repos for, without the sprawl.
- **Robot exemptions from ownership.** Deletes the boundary; the robot writes only where no owner is required.

## Consequences

- Easier: a prod change cannot merge unreviewed while dev stays fast; tenants get self-service with guardrails; the same rule that locks `base/` is what safely unlocks an ephemeral-environments path with bounded exemptions.
- Harder: on a free plan with a private repo, owner review is requested but not required; `path-gate` still reports.
- Follow-up: the blast-radius policy gate fails a PR whose changes under an exempted path render output outside that area.

## Where it is taught or enforced

Rule 5.4 (the ladder only gates what lives on a rung); stage 12 (the rendered diff), stage 21 (`CODEOWNERS`, `ruleset require-owners`, `scripts/path-gate`); the leak-posture appendix.
