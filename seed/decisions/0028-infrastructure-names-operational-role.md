# 0028. `infrastructure/` names an operational role, and controllers are workloads with lifecycles

- **Status:** accepted
- **Date:** 2026-08-13
- **Deciders:** blairforce1, with Claude Code
- **Supersedes:** none

## Context

Filing an ingress controller raised the question of whether `infrastructure/` is misnamed: later arrivals such as KEDA, cert-manager or external-dns are not "technically infrastructure". At the same time the ingress controller the platform would have used, ingress-nginx, was retired upstream (maintenance ended March 2026) and AKS's managed NGINX in the app-routing add-on sunsets in November 2026. A controller is not a fixture; it is a workload that gets replaced.

## Decision

`infrastructure/` stays, because the taxonomy test is who owns it and what depends on it, not what category the software sits in: cluster-scoped controllers the platform team runs and workloads depend on are one role, distinct from `apps/`. It is Flux's own convention, so readers arriving from the Flux docs map the layout instantly. The growth path is a split by reconcile-order dependency, `infrastructure/controllers/` before `infrastructure/configs/`, never by semantics. The ingress controller is Traefik (chart pinned), which speaks both the Ingress API and the Gateway API, where AKS is heading. The retirement is the lesson: controllers are workloads with lifecycles, so swapping one is a change that rides the ladder by PR, rehearsed as platform promotion rather than met as a crisis.

## Considered options

- **`charts/`.** Names the mechanism, not the role, and the folder holds HelmRelease CRs, not charts.
- **`platform/`.** Collides head-on with the `platform` cluster class.
- **`addons/`.** Implies optional; ingress is not.
- **`cluster-services/`.** Overloads a loaded Kubernetes word for no gain.
- **ingress-nginx.** Retired upstream; its managed AKS counterpart sunsets.

## Consequences

- Easier: `infrastructure/` versus `apps/` is one question (who owns it, what depends on it); the ingress swap is the worked example of the platform riding the ladder.
- Harder: the Ingress-to-Gateway-API migration is queued for the absorption act, where AKS moves the layer.
- Follow-up: platform components pin in the class overlay only, so one pin authority exists per rung.

## Where it is taught or enforced

Rule 5.11; stage 05 (Traefik via HelmRelease), stage 13 (change the ingress by PR up the ladder).
