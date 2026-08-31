# 0034. Renovate, not Dependabot, for the config repo; both where they cannot meet

- **Status:** accepted
- **Date:** 2026-08-28
- **Deciders:** blairforce1, with Claude Code
- **Supersedes:** none

## Context

The platform is a workload: chart bumps, controller upgrades and Flux itself promote through the ladder like app changes, and the engine for that is dependency automation. Dependabot has no managers for Flux HelmRelease chart versions, Kustomize image pins or custom version files, so it cannot see most of what a config repo pins. Timely remediation is also the patching control an auditor asks about, so the automation is part of the evidence.

## Decision

Renovate runs on the config repo: Flux, Helm and Kustomize managers, plus custom managers for `clusters/versions.yaml`, entering at the platform overlay (the platform ladder's entry rung, [0017](0017-automation-writes-only-at-the-entry-rung.md)) with the parity gates as companion checks. Dependabot runs on the app repo, for the Dockerfile base image and the Actions pins, where the two tools cannot meet. The hosted Renovate app is a trust trade stated openly; self-hosting (a scheduled workflow plus an owned credential) is the named escape hatch. Renovate is not the vehicle for release waves: it answers "does an upstream datasource have something newer", and a wave's upstream is the repo's own faster channel plus a clock plus metrics.

## Considered options

- **Dependabot everywhere.** Blind to Flux, Helm and Kustomize pins.
- **Hand-rolled bump scripts.** The pin-move automation a previous fleet ran and regretted as heavy.
- **Renovate for waves.** A custom datasource over the repo's own files fights the tool.

## Consequences

- Easier: dependency PRs ride the ladder with rendered diffs; the parity gates flag toolchain moves when Flux moves.
- Harder: two tools, two configurations, one trust decision about a hosted app.
- Follow-up: secret version re-pins can ride the same mechanism at the entry rung, never auto-merged to prod.

## Where it is taught or enforced

Rule 5.11; stage 13 (platform promotion, Renovate), stage 16 (the version ladder); the app repo's Dependabot configuration.
