# 0013. `clusters/<class>/<cluster>/`, and the local cluster is a first-class rung

- **Status:** accepted
- **Date:** 2026-08-07
- **Deciders:** blairforce1, with Claude Code
- **Supersedes:** none

## Context

A config repo's folder shape is an authorization model, a blast-radius map and a promotion ladder at once, and it is the hardest thing to change later: every path-keyed gate, CODEOWNERS line and Flux entry point references it. Flux's own multi-cluster example uses a two-level `clusters/<env>/<cluster>` shape. Readers ask the same question every time: is there a folder per developer, and where does the laptop cluster go?

## Decision

`clusters/<class>/<cluster>/`: the class level (`platform/`, `dev/`, `prod/`) groups its clusters and holds class-shared config; each cluster instance (`dev/dev-01`, `prod/prod-01`) holds its own bootstrap and Flux entry points, and nothing cluster-specific lives outside its instance folder. The local cluster is committed as `clusters/platform/local-01` and is the first rung of the promotion ladder platform → dev → prod. One committed folder serves every throwaway kind replica; per-developer divergence is by feature branch, never by folder edits. The layout is adopted while it looks unnecessarily deep for one cluster, because the folder costs nothing now and a restructure later costs a migration. Beside it, Flux's monorepo shape: `apps/`, `infrastructure/`, `clusters/`, later `policy/` and `tenants/`.

## Considered options

- **Flat `clusters/<cluster>/`.** No home for class-shared config, and class has to be inferred from a name.
- **Per-act or per-stage folders.** Duplicate what git history gives free, force a re-point commit per act, and prefix every path-keyed gate with a token that means nothing in production.
- **A folder per developer.** N folders that drift; the branch already provides per-developer divergence at zero cost.
- **Branch per environment.** The famous anti-pattern: environments become merge conflicts and promotion becomes a cherry-pick.

## Consequences

- Easier: the promotion ladder falls out of folders that already exist; adding a cluster is an addition, not a restructure; `platform/local-01` is both the first rung and environment zero, a laptop replica of the whole platform.
- Easier: CODEOWNERS on `/clusters/prod/**` covers a whole class; the folder is the cluster's inventory ([0015](0015-bindings-live-in-the-cluster-folder.md)).
- Harder: the two-level shape has to be defended at stage 03 when one cluster exists.
- Follow-up: the kind dev and prod clusters are stand-ins with a planned retirement; AKS clusters join the fleet as new members by binding-move PR and the stand-ins retire.

## Where it is taught or enforced

Rule 1.1 and the vocabulary (`class`, `ladder / rung`); stage 03 (bootstrap lands in `clusters/platform/local-01/`), stage 07 (`dev-01`, `prod-01` join); `scripts/cluster-up`, `scripts/cluster-sync`.
