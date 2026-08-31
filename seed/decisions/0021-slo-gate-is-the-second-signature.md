# 0021. Promotion needs two signatures: convergence and a clean SLO window

- **Status:** accepted
- **Date:** 2026-08-19
- **Deciders:** blairforce1, with Claude Code
- **Supersedes:** none

## Context

A GitOps loop can gate promotion on convergence evidence only: the stamp is Ready, the commit wears a green. Ready is a resource fact; whether users are served is a different fact, and the two diverge in the most ordinary way: a static `/healthz` endpoint makes a bad storage configuration Ready-and-green while every real request fails. A release like that climbs to prod on green alone. Detection beyond Ready and gating on it were the missing layer.

## Decision

Promotion to a rung requires **two signatures**: convergence (the green context on the rung below) and performance (`slo-gate`: the rung below met its SLO over a soak window). The ingress is the first SLI source (per-service request and duration metrics, no app changes). The SLO is policy in git: a `PrometheusRule` on the hub only (agents ship, the hub judges), a 99%/30d target, recording rules with stable names, one fast-burn alert. `slo-gate` looks backward over a window, so a recent incident blocks promotion until it ages out; window semantics are the soak. **No traffic is a FAIL**: absence of evidence is not health. Security signals (CVEs, signatures, SBOMs) are a third evidence class on different clocks, deliberately excluded from the gate: per-change gates run at entry and admission, and CVE signal is an asynchronous remediation loop, not a promotion window.

## Considered options

- **Convergence only.** Ships the Ready-but-failing release.
- **Pod-level canary analysis (Flagger).** A different layer; the platform gates which rung gets the release, not which request hits the new version.
- **Treat no traffic as pass.** A canary that serves nobody would wave everything through.
- **Fold security signals into the gate.** Different clocks; a CVE verdict against an already-green release is a rollout, not a window.

## Consequences

- Easier: the drill that ships a well-formed wrong connection string proves every other gate waves it through and only the SLI catches it.
- Harder: the ServiceMonitor for the ingress has to live with the monitoring variants, not the ingress release, or a fresh rebuild deadlocks on CRDs that do not exist yet.
- Harder: per-tenant SLOs mean one customer's error budget can block a promotion, a business conversation to have before 2am ([0031](0031-a-tenant-is-a-replica-an-environment-is-a-rung.md)).
- Follow-up: multiwindow burn-rate alerting is the production extension, named and not built.

## Where it is taught or enforced

Rule 5.7; stage 09 (SLIs, the SLO rule, the drill), the Act III checkpoint drill 2; `scripts/slo-gate`, `scripts/slo-watch`.
