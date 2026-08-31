# 0032. An ephemeral PR environment is an ephemeral tenant: a loosened folder, teardown on close, a reaper that is not optional

- **Status:** accepted
- **Date:** 2026-08-07
- **Deciders:** blairforce1, with Claude Code
- **Supersedes:** none

## Context

Developers ask for a full environment per pull request, for CI, manual and acceptance testing, destroyed afterwards. The naive form is a throwaway cluster pointed at a feature branch, which works for one developer and does not scale or leave a record. A branch per environment scatters live state across refs, needs its own garbage collection, and still requires something on `main` pointing at it. Approval is often followed by further pushes, so it is the wrong teardown trigger. The action that creates environments will someday fail to fire, and an orphaned environment is a silent cost.

## Decision

An ephemeral environment is a stamp per PR: `environments/ephemeral/` holds one file per live environment (a Flux source plus a Kustomization pointing at the PR's config and the PR-built image tag, with source repo, PR number, created-at and TTL as metadata). The app repo's workflow commits the file to create and removes it to destroy; Flux prune does the teardown; the live set is `ls` of one folder. The folder is loosened with proof, not hope: CODEOWNERS exempts it because the exemption is bounded three ways (the blast-radius policy gate fails any PR whose changes under the path render output outside the ephemeral area; an environment is a short-lease tenant with the tenancy stage's isolation; the bot's write access is path-scoped). Teardown on merge or close, never on approval. A scheduled reaper removes entries past TTL or whose PR closed; it is non-negotiable. Each environment gets its own storage emulator and a wildcard ingress host, and the workflow registers a deployment so the URL appears on the PR.

## Considered options

- **A branch per environment.** Scatters state, needs its own GC, still needs a pointer on `main`.
- **A whole cluster per PR.** The naive demo form; no record, no isolation story, no fleet.
- **Teardown on approval.** Ends the acceptance phase before the last push.
- **No reaper, trust the action.** Orphans as a cost leak.

## Consequences

- Easier: environment per PR in minutes with a URL on the PR; the orphan count is a listing; the governance model flexes (the rule that locks `base/` is what safely unlocks this path).
- Harder: cross-repo wiring between the app repo's workflow and the config repo, with a path-scoped credential for the bot.
- Follow-up: this is a trunk stage because it is the developer request that never goes away, not optional material.

## Where it is taught or enforced

Stage 25 (ephemeral PR environments as ephemeral tenants), stage 07 (the naive form it retires), stage 12 and 21 (the bounded exemption); rule 5.1 (a loop per PR).
