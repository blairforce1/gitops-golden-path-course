# 0014. Class is binary, and policy attaches to class, never to name

- **Status:** accepted
- **Date:** 2026-08-11
- **Deciders:** blairforce1, with Claude Code
- **Supersedes:** none

## Context

Fleets accumulate named environments: staging, QA, demo, canary, UAT, pre-prod. Each one wants its own alert routing, monitoring depth, backup inclusion, access control and change gating, and every fleet ends up with N environments and N slightly different policy bundles. The usual lie is a "staging" that holds customer data under dev controls; nothing in a name-keyed policy model can even express that this is wrong.

## Decision

Every environment, cluster, stamp and release channel member carries exactly one *class*, `dev` or `prod`, distinct from its *name*. Policy attaches to class, never to name: alert severity and routing, monitoring depth, backup and DR inclusion, access control, change gating, sops key scope. N environments, two policy bundles. A prod-side canary is name `canary`, class `prod`. The forcing function is the point: if "staging" holds customer data it is class `prod`, and the binary makes the usual staging lie impossible to state. Class is declared on the binding and in the folder level, never inferred from a channel or a position.

## Considered options

- **Policy keyed by environment name.** The default and the source of the drift.
- **Three or more classes (dev, test, prod).** Every extra class is a place to hide prod data under weaker controls; two is the smallest set that forces the question.
- **Class derived from the release channel.** Conflates exposure with kind of cluster; a dogfood tenant on a prod-class cluster becomes inexpressible ([0016](0016-release-channels-as-a-label-ascent-judged-where-members-exist.md)).

## Consequences

- Easier: two policy bundles; a new named environment is a folder and a class label, nothing else; the sops key scope and the version-ladder pin follow the same split.
- Harder: the question "is this prod?" must be answered honestly for every environment, which is uncomfortable exactly where it matters.
- Follow-up: the `platform` cluster is a third *folder level* for ladder purposes but carries class semantics of its own (the rung nobody misses); the vocabulary table keeps *class* and *rung* distinct.

## Where it is taught or enforced

Vocabulary entry `class`; stage 02 (the `platform.example.com/class` label at its starter value), stage 07 (the split made real across three clusters), stage 22 (a canary-channel tenant on a prod-class cluster proves the axes independent).
