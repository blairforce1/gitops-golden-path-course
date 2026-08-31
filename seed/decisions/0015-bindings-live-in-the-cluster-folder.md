# 0015. Bindings live in the cluster folder; folders encode identity, never schedule

- **Status:** accepted
- **Date:** 2026-08-11
- **Deciders:** blairforce1, with Claude Code
- **Supersedes:** none

## Context

A fleet has three artefacts wanting three homes: the stamp definition (workload config and variants, cluster-agnostic), the binding (the Flux `Kustomization` CR: path or pin, interval, `dependsOn`, health checks, inherently per (cluster, stamp)), and the cluster inventory (which bindings a cluster runs). The binding is the edge in the cluster → stamp graph. A previous fleet pooled CRs under `clusters/stamps/<region>/` behind an aggregating `kustomization.yaml`, which duplicated the region axis into a second tree and made consumption all-or-nothing; the same fleet encoded release rings as folders, so every ring policy change was a `git mv` rippling through path references.

## Decision

Bindings live in the cluster folder, `clusters/<class>/<cluster>/resources/<stamp>.kustomization.yaml`. No `rings/` or `channels/` tree, no pooled CR folder, no convenience aggregator. Folder taxonomy encodes identity (which cluster, which stamp), never schedule (which channel, which wave); schedule is a label on the binding ([0016](0016-release-channels-as-a-label-ascent-judged-where-members-exist.md)). Region is a cluster property in its identity (`clusters/prod/weu-01`), not a taxonomy layer. The N×M "duplication" of bindings is the data: each carries a genuinely per-pair pin, which is exactly the surface pin-move automation and the rendered diff operate on. Variance posture is structured-first: per-region overlays or components inside the stamp, binding-level `spec.patches` for per-cluster values, and `postBuild.substituteFrom` only for a short allowlist of cluster facts.

## Considered options

- **Pooled CR folder plus aggregator.** The (cluster, stamp) pair, the fleet's fundamental unit, becomes inexpressible; "what runs on cluster X" needs indirection; a deploy-one-stamp edit has every-referencing-cluster blast radius.
- **Ring or channel as a folder.** Every policy evolution is a migration; the fleet whose rings compressed and whose canary moved sides is the proof.
- **Substitution as the default variance mechanism.** Stringly: no schema, `$` escaping, an unset variable passes through, and rendered-in-review is not applied unless CI substitutes per cluster. Demoted to an allowlist.

## Consequences

- Easier: `ls` on the folder is the cluster's stamp inventory, the git-side mirror of `flux get kustomizations`; the blast radius of a binding edit is one cluster; CODEOWNERS on `/clusters/prod/**` covers pipelines and pins with no extra rules; the stamp's channel history is `git log` on one file.
- Easier: a cross-cluster move is delete-here-add-there in one PR, and a dead cluster's folder is the complete pinned inventory of what was running, so DR is a scripted PR ([0038](0038-dr-is-rebuild-not-failover-region-b.md)).
- Harder: where bindings are truly identical across a class, a class-level base plus per-cluster overlay is needed to dedupe; the model does not change.
- Follow-up: the 1:1 mapping between a binding and a stamp is load-bearing: independent failure domains, per-stamp gates, per-stamp halt (`suspend`), per-stamp pin, an enumerable fleet.

## Where it is taught or enforced

Vocabulary entries `stamp` and `binding`; stage 03 (the first binding), stage 07 (the layout at n=3), stage 22 (bindings per tenant), stages 28–29 (labels as schedule); `scripts/evidence` reads the binding by path.
