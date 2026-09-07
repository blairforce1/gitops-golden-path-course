# 0012. Follow the authority, at the pace Kubernetes sets

- **Status:** accepted
- **Date:** 2026-08-11
- **Deciders:** blairforce1, with Claude Code
- **Supersedes:** none

## Context

OSS Flux typically runs a minor ahead of the release bundled in AKS's `microsoft.flux` extension, so the reflex `curl | bash` install grabs a version ahead of the fleet, the wrong direction. The claim that the cloud can absorb a hand-built platform is only honest if versions agree. The Kubernetes ecosystem already has a version discipline: a versioned API, bounded skew for every tool (kubectl one minor either side of the server), upgrades one minor at a time. A fleet is always mid-rollout, so a single Kubernetes version for every cluster is a fiction.

## Decision

Versions are followed, never chased. Every pin tracks its authority's current release ([0010](0010-one-authority-per-tool-kubectl-never-renders.md)); the local Flux mirrors the AKS extension's bundled release. The fleet's Kubernetes version climbs a ladder: platform first, then dev, then prod, each class at most one minor behind the next, recorded in `clusters/versions.yaml` and climbed one rung per change. The same order carries chart bumps and controller upgrades. `check-flux-aks-parity` scrapes the extension release notes and compares (FAIL on minor drift with the pin command, WARN if the scrape breaks); it runs at stage starts and on a CI schedule.

## Considered options

- **Latest OSS Flux.** Runs ahead of the fleet's eventual authority; the absorption diff would be a downgrade.
- **One Kubernetes version fleet-wide.** Not how a real fleet looks; the ladder is what lets a minor soak somewhere nobody misses before it reaches prod.
- **Pin and forget.** Drift is silent; the scheduled parity check exists so that drift surfaces without anyone remembering to look.

## Consequences

- Easier: the platform → dev → prod split gives the version policy its rungs for free; the fleet stays inside every tool's tested skew window.
- Harder: the ladder spans three minors, so only the middle rung's kubectl legally reaches every cluster; kubectl pins to dev, and mid-rollout the fleet briefly spans four ([0030](0030-kubernetes-ladder-three-minors-kubectl-pins-dev.md)).
- Harder: a scrape of vendor release notes is a dependency on a web page; the gate degrades to WARN rather than failing on scrape breakage.
- Follow-up: on AKS the same ladder maps to per-cluster upgrade channels, with the pins file still the source of truth.

## Where it is taught or enforced

Rule 4.3; stage 00 (the toolchain gate), stage 07 (the ladder recorded), stage 16 (the ladder climbs), Act VIII (the managed extension the pin anticipated); `scripts/check-flux-aks-parity`, `scripts/check-version-ladder`, `clusters/versions.yaml`.
