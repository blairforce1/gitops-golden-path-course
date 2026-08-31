# 0001. Use Flux, not Argo CD

- **Status:** accepted
- **Date:** 2026-08-04
- **Deciders:** blairforce1, with Claude Code
- **Supersedes:** none

## Context

A GitOps platform needs one reconciler, and the two credible candidates are Flux and Argo CD. The platform's target cloud is Azure, where - when this was decided - the only managed GitOps offering was the `microsoft.flux` AKS extension, which installs and lifecycles Flux controllers. A platform built by hand on Flux can later be absorbed by that extension with a small, readable diff. (Context updated 2026-08-31: Azure now also offers Argo CD as a managed extension, `Microsoft.ArgoCD`, for AKS and Arc-enabled clusters - in preview, with workload identity federation and Entra SSO - so the "no managed counterpart" half of the original argument no longer holds. The decision stands on the reasons below that do.) The two tools also differ in shape: Flux is a set of controllers driven by CRs with no UI in the box; Argo CD is an application with a UI, an RBAC model of its own and an ApplicationSet abstraction.

## Decision

The platform uses Flux throughout: source-controller, kustomize-controller, helm-controller, notification-controller, image automation, all driven by CRs in git. Argo CD is described once, as an honest comparison, and never runs. The reason that carried it in August 2026 was the endgame: when the cluster becomes AKS, the managed extension takes over the same controllers, the same CRs and the same repo shape, so nothing built by hand is thrown away. With a managed Argo CD extension now available, the reasons that still carry it: Flux is operated entirely through CRs in git with no UI as an operating surface, which is this platform's whole thesis (git and the commit status are the interface); the notification loop, the commit statuses and the evidence chain are built on Flux's event model; `microsoft.flux` is generally available while `Microsoft.ArgoCD` is in preview; and the absorption stage is written against Flux. A team choosing Argo CD today inherits the platform's *shape* unchanged - repo layout, PR discipline, rungs, identifiers, gates and evidence are reconciler-agnostic; only the reconciler's own CRs change.

## Considered options

- **Argo CD.** Better first-hour experience (UI, app-of-apps, ApplicationSets). When decided, no managed Azure counterpart existed; since 2026 one does (`Microsoft.ArgoCD`, preview), so the remaining objection is the operating model: the UI and Argo's own RBAC become the operating surface instead of git and the commit status, and `Application` becomes the unit rather than a plain CR the repo layout maps onto. Rejected for this platform; a legitimate choice for a team, and the platform shape transfers.
- **Both, as parallel tracks.** Doubles every stage and teaches comparison rather than operation; rejected.
- **Managed Flux from the start.** Hides the controllers the operator has to understand at 3am; the managed version is the payoff, not the starting point ([0029](0029-managed-first-disposable-infrastructure-in-place-patches.md), rule 5.12).

## Consequences

- Easier: one CR vocabulary for sources, stamps, Helm releases, alerts and receivers; the AKS migration is a version pin, not a re-platform; local Flux pins to the AKS-bundled release ([0012](0012-follow-the-master-at-kubernetes-pace.md)).
- Harder: no UI in the box. Fleet visibility has to be built (kube-state-metrics custom-resource state, Grafana), which the platform does deliberately so that the dashboard reads the same evidence the gates read.
- Harder: Flux's `Kustomization` CR shares a name with kustomize's `kustomization.yaml`; the vocabulary term *stamp* exists to keep sentences unambiguous.
- Follow-up: Flux receives CDEvents but does not emit them; the outbound half is a separate translator, briefed outside this repository.
- Follow-up: revisit when `Microsoft.ArgoCD` reaches general availability; the README's comparison section states what would and would not change.

## Where it is taught or enforced

Rule 1.1 and the vocabulary table in `rules.md`; the Flux-versus-Argo section of the course README; `scripts/check-flux-aks-parity`. Course consequence: the local-first spine on kind with AKS as the capstone.
