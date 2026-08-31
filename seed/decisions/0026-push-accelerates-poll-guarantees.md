# 0026. Push accelerates, poll guarantees, keep both; the interval is a trust dial

- **Status:** accepted
- **Date:** 2026-08-11
- **Deciders:** blairforce1, with Claude Code
- **Supersedes:** none

## Context

Unaided merge-to-running is dominated by the source's poll interval: roughly seventy seconds at a one-minute interval, most of it waiting for the fetch. Shortening the interval to buy latency multiplies load across a fleet (N clusters × M sources polling git and the registry). Flux's notification-controller has an inbound counterpart to Alert and Provider: a `Receiver` that accepts a webhook from the forge or from CI and annotates the source so it fetches now. Flux receives CDEvents (`Receiver` v1 carries the type) but does not emit them; no `Provider` type does.

## Decision

The build tells the fleet rather than the fleet polling: a `Receiver` per source, HMAC-validated, poked by the forge on push and by CI when an artifact is published. Push carries the latency, poll stays as the guaranteed floor, and the acceptance test is stated: kill the webhook and the fleet must still converge, just slower. The poke inverts the interval economics: with push carrying latency, source intervals stretch from minutes to tens of minutes, a real load reduction at fleet scale. How far they stretch is a trust dial, not a performance knob: the reconcile sweep is a compensating control for direct cluster access, so where humans have no write path to the cluster, drift has no author and the interval stretches safely; where humans still touch clusters, the interval is the sweep cadence and the bound on how long an unratified manual change can live. The source interval stretches nearly free; the Kustomization interval is the drift-correction bound and stretches only with the access model. `Receiver.spec.resources` is an allowlist, the same scoping lesson as `Alert.spec.eventSources`, inbound. CI never touches the API server: it hits an HTTP endpoint.

## Considered options

- **Short poll intervals.** Latency bought with fleet-wide load and rate limits.
- **`flux reconcile --with-source` from CI.** Cluster credentials in CI; the receiver is the same operation without them.
- **Event-driven only, no poll.** Webhook delivery is best-effort; a lost event is a stalled fleet.

## Consequences

- Easier: merge-to-running drops to seconds; the lead-time metric splits into webhook-hit and interval-fallback.
- Harder: a publicly reachable receiver endpoint only honestly exists where the forge can deliver to it; on a laptop fleet the mechanism is taught and the endpoint is simulated.
- Follow-up: the outbound half (a service was deployed) is a stateless translator briefed outside this repository, not an operator, because `Alert` and `Provider` are already the configuration surface; events for correlation and timeliness, artifacts for truth and retroactivity.

## Where it is taught or enforced

Stage 04 (the interval named as the floor), stage 15 (the receiver, the acceptance test); rule 5.1.
