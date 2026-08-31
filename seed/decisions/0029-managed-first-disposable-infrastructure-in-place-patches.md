# 0029. Managed-first, disposable infrastructure, and in-place for patches and minors

- **Status:** accepted
- **Date:** 2026-08-13
- **Deciders:** blairforce1, with Claude Code
- **Supersedes:** none

## Context

Running Kubernetes is an operational burden, and most of it is the parts a cloud will run for you. Many changes are easier as "bring up new infrastructure and migrate the workload" than as in-place retrofit, and a platform whose cluster rebuild is rehearsed and cheap lowers the stakes of every architecture decision. But some changes are the opposite: security patches and Kubernetes version upgrades are safer in place, tested rung by rung, because managing them audits the configuration (pod disruption budgets, surge headroom, deprecated APIs, workload assumptions) and the shortcomings surface on the platform rung instead of in prod. A cloud cluster takes thirty minutes to create, not seventy seconds.

## Decision

Managed-first: adopt the managed version of a service where one exists; the hand-build-then-absorb arc teaches what the managed service does and never argues for self-hosting it. Infrastructure, clusters especially, is disposable: shape changes, controller swaps and regretted choices migrate to new infrastructure by binding-move PR, and migration forgives. Routine currency (patches, Kubernetes minors) moves in place up the ladder. The posture only pays if it is embedded, automated and regularly tested: the cluster and bootstrap scripts are the automation, the act checkpoints and drills are the testing, and the platform-from-nothing number is the doctrine, measured. In the cloud the cadence changes, not the approach: bring the new cluster up alongside and migrate (blue/green at cluster scale) rather than tolerate a rebuild gap.

## Considered options

- **Self-host everything for control.** The burden the managed service exists to remove; the course builds by hand to teach, not to recommend.
- **Replace for everything, including patches.** Loses the audit that in-place upgrades perform on the configuration.
- **In-place for everything.** Regretted choices become permanent liabilities.

## Consequences

- Easier: the fleet layout's binding-move PR is the migration mechanism for every kind of replacement; AKS clusters join the fleet as new members and the stand-ins retire.
- Harder: two mechanisms, chosen by change type, have to be taught as a pair.
- Follow-up: on a laptop fleet kind cannot upgrade in place, so the version ladder is simulated by rebuild per rung ([0030](0030-kubernetes-ladder-three-minors-kubectl-pins-dev.md)); the managed cluster does it for real.

## Where it is taught or enforced

Rules 5.11 and 5.12; stage 05 (the act opens with a rebuild), stage 16 (the ladder climbs), Act VIII (absorption by binding-move PR).
