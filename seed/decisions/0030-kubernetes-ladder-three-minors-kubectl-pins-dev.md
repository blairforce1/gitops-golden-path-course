# 0030. The Kubernetes ladder spans three minors, and kubectl pins to the dev class

- **Status:** accepted
- **Date:** 2026-08-12
- **Deciders:** blairforce1, with Claude Code
- **Supersedes:** none

## Context

A real fleet is always mid-rollout: no single Kubernetes version describes it. kubectl supports one minor either side of the server, so across a three-minor fleet only one client version legally reaches every cluster. Workstation tools drift ahead of every authority by default. A fleet that pins one version everywhere either upgrades everything at once or lies about it.

## Decision

The fleet deliberately spans three minors: platform tests next, dev runs current, prod runs stable, each class at most one minor behind the next. Pins live in `clusters/versions.yaml`, a git-managed class fact that `cluster-up` consumes, so upgrading a rung is a one-line PR, and the climb walks bottom up, promote before pin: prod onto dev's minor once dev has soaked it, dev onto platform's, then the new minor enters at platform when the authority offers it. kubectl pins to the dev class, the middle rung, the only one that reaches every cluster, and the dev upgrade PR bumps the kubectl pin in the same diff. `check-version-ladder` enforces the shape. On a managed cluster the same ladder maps to per-cluster upgrade channels with the pins file still the source of truth.

## Considered options

- **One version fleet-wide.** Not a fleet; an upgrade is a big bang.
- **kubectl at latest.** Illegal against prod for part of every rollout.
- **Per-cluster kubectl.** Possible, but the ladder exists so that one client suffices except mid-rollout.

## Consequences

- Easier: a minor is proven on the rung nobody misses before it reaches prod; the ladder is visible in one file.
- Easier: walked bottom up, the fleet never spans more than three minors mid-climb, so the pinned kubectl reaches every cluster at every step, and the rung the window dropped is the first to move.
- Amended 2026-09-06 (stage 16's pre-flight, with the author): the climb was top-down (platform first, soak, walk down), which left prod on the unsupported minor longest and spanned four minors mid-climb; it is bottom up. The window is a deadline, not a trigger: a team may promote prod and dev before it is forced and take the platform pin separately, keeping the same two constraints.
- Amended 2026-09-07 (stage 16, with the author): the promotions are deliberate, on the rung above's soak, and the pin follows the authority's calendar; the window is the deadline the parity gate watches, not the trigger. Stage 16 always makes the prod promotion, offers the dev promotion on the same evidence, and pins platform only when the window offers a minor above it, so the fleet never spans four minors and one kubectl reaches every cluster.
- Harder: on a laptop fleet the ladder is rebuild-per-rung, since kind cannot upgrade in place.
- Follow-up: the dev rung is the client-tooling authority for helm as well ([0010](0010-one-authority-per-tool-kubectl-never-renders.md)).

## Where it is taught or enforced

Rule 4.3; stage 07 (the ladder recorded), stage 16 (climbing it); `scripts/check-version-ladder`, `clusters/versions.yaml`.
