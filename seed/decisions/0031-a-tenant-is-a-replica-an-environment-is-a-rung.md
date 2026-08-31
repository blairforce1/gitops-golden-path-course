# 0031. A tenant is a replica, an environment is a rung, and one stamp per tenant

- **Status:** accepted
- **Date:** 2026-08-24
- **Deciders:** blairforce1, with Claude Code
- **Supersedes:** none

## Context

The `dev` and `prod` overlays of a single-tenant repo carry two meanings at once: which rung and which instance. That holds only while the two coincide. Both classic multi-tenancy failures are collapses of the distinction: tenants treated as rungs produce review theatre and changes that "climb" into customers; environments treated as tenants are branch-per-environment in a directory costume. A shared stamp with `wait: true` means one customer's bad image is every customer's change freeze. A per-cluster availability figure is an average across customers and hides the one having a bad day.

## Decision

An **environment is a rung**: sequential, evidence-gated, divergence intentional and shrinking. A **tenant is a replica**: parallel, identical by default, divergence intentional and permanent. Identity leaves the base (the namespace and the `tenant` label move to the tenant leaf, because a base that cannot say who it belongs to can belong to anyone); a single inheritance chain, base → `overlays/<env>` → `tenants/<tenant>/<env>`; the image pin stays on the environment, so a promotion still moves one line and every tenant on the rung receives it, and a per-tenant pin is a deliberate, greppable exception (the dogfood tenant is that exception used on purpose). One stamp per tenant, because a stamp is a blast radius. The SLO gains a tenant dimension, so `slo-gate` becomes a per-tenant question and one customer's error budget can block a promotion. `.sops.yaml` rules follow the folders, so tenancy is the encryption boundary. Tenant data isolation is a ladder: shared account with per-tenant containers (naming, not isolation), then an account per tenant with its own key in a per-tenant secret, then real accounts with RBAC-scoped identities. Exit criteria for explicit folders are stated (copy-paste is the only way to add a tenant; a fleet-wide change edits N leaves), with the replacements in order of commitment and an instruction not to pre-build any of them.

## Considered options

- **Tenants as overlays beside environments.** Rung and instance conflated; the first failure above.
- **A shared stamp for all tenants.** Coupled blast radius; the drill proves it in both directions.
- **Per-tenant image pins by default.** Promotion becomes N PRs and the ladder fragments into per-customer schedules; that is what release channels and waves are for ([0016](0016-release-channels-as-a-label-ascent-judged-where-members-exist.md)).
- **A tenancy operator from the start.** The last rung of the exit ladder, built only when the folders stop scaling.

## Consequences

- Easier: tenant onboarding is one PR; cross-tenant access provably fails; the noisy-neighbour drill has a per-tenant SLO to show.
- Harder: per-tenant SLO gating is a business conversation to have before 2am.
- Follow-up: an ephemeral PR environment is an ephemeral tenant on the same machinery ([0032](0032-ephemeral-pr-environment-is-an-ephemeral-tenant.md)); tenants will build their own release semantics inside whatever channel they are given, so design expecting it.

## Where it is taught or enforced

Stages 22 (the second axis), 23 (tenant access), 24 (tenant data); `scripts/slo-gate --tenant`; the Act VI checkpoint's noisy-neighbour drill.
