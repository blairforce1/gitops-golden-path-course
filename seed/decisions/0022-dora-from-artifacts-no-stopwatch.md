# 0022. DORA is computed from artifacts, production-scoped, one change is one unit, and nothing is timed by hand

- **Status:** accepted
- **Date:** 2026-08-25
- **Deciders:** blairforce1, with Claude Code
- **Supersedes:** none

## Context

The four DORA metrics are usually claimed from a spreadsheet. The loop's own records (commit timestamps, per-context status `created_at`, condition transitions, metric samples) already contain them. Two wrong computations are easy: counting a stamp's `revision` label changes reports every push as a deployment (a 10× overcount), and averaging per-cluster rates gives a fleet rate no cluster has. One change reaching fifty tenants is not fifty deployments, or the metric scales with customer count. A commit can wear a green the cluster has not earned yet: a reconcile begun before the fetch posts success on the fresh commit while the old workload still runs.

## Decision

Every number the platform records comes from artifacts, never a stopwatch: rebuild time, lead time per rung, detection time, the four DORA numbers. **Production is the scope**; other rungs are diagnostics, labelled not-DORA. **The unit is the change**, not its application: one commit reaching every tenant is one deployment. **Lead time ends at the first production arrival**, because the feedback signal exists as soon as the change serves real traffic; first-to-last arrival is a separate line, `convergence`. Deployments count from `kube_deployment_metadata_generation`, which moves only on a real spec change. Every partition (stamp, cluster, tenant, class, fleet) is recomputed from raw samples; no summary is an input to another. Lead time decomposes (`--stages`) into dev → PR, review, merge → prod using the version token the commit convention puts in both subjects. Contaminants (dependency-ordering cascades, retention cliffs, an overnight break) are named in the output rather than hidden. The metrics are optimised for meaning, not tamper-resistance; the hazard is inadvertent gaming and it is tabulated.

## Considered options

- **Stopwatch or spreadsheet.** A claim, not evidence.
- **Count revision changes.** Reconcile is not change; wrong by 10× on a real fleet.
- **Lead time to the slowest tenant.** Folds customer freeze calendars into a delivery-capability metric.
- **Mean of per-cluster rates.** Counts sum; rates and percentiles do not.

## Consequences

- Easier: the same artifacts feed `rung-time`, `detect-time`, `dora` and the evidence dossier, so the audit trail and the delivery metrics are one dataset.
- Harder: the measurement must wait for the cluster to report `lastAppliedRevision` for the commit and for the rollout to finish before reading a status; a status is stamp telemetry, never a verdict on a commit.
- Harder: Prometheus retention shorter than the window under-reports; the tool warns and recomputes rates over the span covered.
- Follow-up: the app repo's source commit and CI build remain outside lead time; CDEvents could close that gap.

## Where it is taught or enforced

Rule 5.8; stage 10 (the four numbers), every act checkpoint; `scripts/dora`, `scripts/rung-time`, `scripts/detect-time`, `scripts/evidence`.
