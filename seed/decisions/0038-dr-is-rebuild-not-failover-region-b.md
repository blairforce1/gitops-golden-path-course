# 0038. DR is rebuild, not failover; the drill is region B; geo-redundancy without an SLA is a hope

- **Status:** accepted
- **Date:** 2026-08-27
- **Deciders:** blairforce1, with Claude Code
- **Supersedes:** none

## Context

A previous fleet ran active/active regional clusters with customers placed by proximity, tried paired regions with geo-replicated storage, and effectively abandoned them: geo-replication carries no RPO SLA, and a paired-region failover competes for the pair's capacity with every other affected tenant at the worst possible moment. It looks fine on the diagram and fails in the only scenario it exists for. The mechanism that worked was backups and clones. The final posture accepts the risk profile of Availability Zones: zone redundancy inside the region is the resilience primitive, deemed good enough for everything short of a full-region outage, which makes data backup plus rebuild in a different region the deliberate last resort rather than the first response - and is why full DR is a recreate, not a failover. A regional event is also a shared one: you evacuate alongside every other affected customer of the same cloud, so competing for capacity is part of the DR strategy itself - the reason the posture says rebuild anywhere *with capacity* rather than rebuild in a named pair, and why the drill treats region as a parameter, not a constant. And the platform does not get the last word (context completed 2026-08-29): the application workloads and the contractual SLA - ideally derived from engineering reality rather than imposed by marketing - dictate what DR can and should be. Some applications are built multi-region with globally replicated data and barely need the drill; others carry constraints no platform posture can lift. The rebuild posture is the platform's floor, not every workload's ceiling. Data sovereignty is a tenant attribute that constrains placement and rebuild targets.

## Decision

GitOps converts DR from failover to rebuild: the platform definition is already replicated in git, so only data needs a replication strategy. A dead cluster's binding folder is the complete pinned inventory of what was running, in a system that did not die with the region; moving it is the cross-cluster move in bulk, scriptable, divisible across survivors, with the dead cluster's folder emptied in the same PR so a returning cluster prunes instead of resurrecting split-brain state (`suspend` is the wrong fence; file deletion is the fence). Zone redundancy is the resilience primitive; regional clusters are retained for proximity and blast radius; backups are maintained and restored in the drill, because an untested backup is a hope. The regional drill rebuilds in a different region with the first presumed dark, which forces region as a parameter, identity re-federation against the new cluster's issuer, and the honest RPO conversation about storage; RTO and RPO come out as measured numbers from artifacts. Data has gravity: the move relocates compute and config; geo-replication of data belongs to the platform substrate.

## Considered options

- **Paired-region failover with GRS.** No RPO SLA; capacity contention at the worst moment.
- **Rebuild in the same region.** Re-running the deployment in place is not a DR claim.
- **`flux suspend` as the fence for a dead cluster.** Freezes reconciliation, leaves workloads running.

## Consequences

- Easier: time-to-understand is one `ls`; time-to-restore is one scripted PR plus owner review plus a reconcile interval, a DORA restore number; class-scoped keys make the move PR self-sufficient ([0018](0018-secrets-taxonomy-class-keys-roll-forward.md)).
- Harder: one regional partitioning serves proximity, blast radius, waves and legal boundaries at once, elegant until one dimension needs to differ.
- Harder: the regional drill is the first that costs money and sits behind an explicit flag with a printed estimate.
- Follow-up: the layout scenarios (re-channel a stamp, move a stamp, lose a cluster) are worked examples on the same mechanism ([0015](0015-bindings-live-in-the-cluster-folder.md)).

## Where it is taught or enforced

Rule 5.2 ("nothing" widens to the region); stage 07 (the layout scenarios), the Act VIII checkpoint (rebuild-region).
