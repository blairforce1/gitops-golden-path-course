# 0009. Identifier alignment: one string, seven homes

- **Status:** accepted
- **Date:** 2026-08-24
- **Deciders:** blairforce1, with Claude Code
- **Supersedes:** none

## Context

The cost of a naming decision is only half paid when the name is chosen; the other half is whether the identifier survives the trip from an alert back to the config that caused it. An alert that names a symptom sends the first five minutes of every incident to finding the dashboard. A name that changes shape between the git folder, the kube context, the stamp, the commit status, the metric label and the filename needs a lookup table, and the lookup table is the thing nobody maintains. Half-anonymised fleets pay the translation cost while the real name survives in metric labels, certificates and alert text.

## Decision

The identifier for a thing is the same string everywhere it appears: git folder (`clusters/prod/prod-01/`), kube context (`kind-ggp-prod-01`), stamp (`app-prod`), commit status context (`kustomization/app-prod/prod-01`), metric labels (`gotk_resource_info{name,cluster}`), resource filename (`app-prod.kustomization.yaml`), commit scope (`promote(app-prod):`). Alert payloads carry identifiers, not just symptoms. Anonymise the whole chain or none of it. Each cluster's Provider declares its status-context suffix (`spec.commitStatusExpr`) so identity comes from git, not from a runtime UID.

## Considered options

- **Flux's default status suffix (the Provider's truncated UID).** Accidental identity; unstable across Provider recreation, which orphans the status history thread.
- **A lookup table in a runbook.** Exists in every fleet that skipped this rule, and costs most during the outage.
- **Per-surface naming freedom.** The default; every surface picks a locally convenient name and nothing lines up.

## Consequences

- Easier: from a red status context alone, `evidence` splits stamp and cluster out of the string and opens the right file with no table; the commit scope is the identifier's seventh home, so a subject line reads as a blast radius.
- Harder: renames are fleet-wide events touching seven surfaces; the rule makes that cost visible instead of paying it in fragments.
- Harder: the test has to be run: from the notification alone, can you name the file to open?
- Follow-up: tenant naming versus anonymisation is a separate decision with a scale-based rule ([0025](0025-a-private-repo-is-a-delay-not-a-control.md)).

## Where it is taught or enforced

Rule 3.6; stage 03 (the first stamp), stage 07 (declared per-cluster contexts), stage 09 (metric labels); `scripts/evidence`; `appendices/repo-leak-posture.md`.
