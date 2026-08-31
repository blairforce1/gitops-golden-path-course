# 0030. The Kubernetes ladder spans three minors, and kubectl pins to the dev class

- **Status:** accepted
- **Date:** 2026-08-12
- **Deciders:** blairforce1, with Claude Code
- **Supersedes:** none

## Context

A real fleet is always mid-rollout: no single Kubernetes version describes it. kubectl supports one minor either side of the server, so across a three-minor fleet only one client version legally reaches every cluster. Workstation tools drift ahead of every master by default. A fleet that pins one version everywhere either upgrades everything at once or lies about it.

## Decision

The fleet deliberately spans three minors: platform tests next, dev runs current, prod runs stable, each class at most one minor behind the next. Pins live in `clusters/versions.yaml`, a git-managed class fact that `cluster-up` consumes, so upgrading a rung is a one-line PR that enters at platform, soaks, then walks down. kubectl pins to the dev class, the middle rung, the only one that reaches every cluster, and the dev upgrade PR bumps the kubectl pin in the same diff. `check-version-ladder` enforces the shape. On a managed cluster the same ladder maps to per-cluster upgrade channels with the pins file still the source of truth.

## Considered options

- **One version fleet-wide.** Not a fleet; an upgrade is a big bang.
- **kubectl at latest.** Illegal against prod for part of every rollout.
- **Per-cluster kubectl.** Possible, but the ladder exists so that one client suffices except mid-rollout.

## Consequences

- Easier: a minor is proven on the rung nobody misses before it reaches prod; the ladder is visible in one file.
- Harder: mid-rollout the fleet briefly spans four minors, so no single kubectl legally reaches every cluster; a side-by-side client serves platform during the soak.
- Harder: on a laptop fleet the ladder is rebuild-per-rung, since kind cannot upgrade in place.
- Follow-up: the dev rung is the client-tooling authority for helm as well ([0010](0010-one-master-per-tool-kubectl-never-renders.md)).

## Where it is taught or enforced

Rule 4.3; stage 07 (the ladder recorded), stage 16 (climbing it); `scripts/check-version-ladder`, `clusters/versions.yaml`.
