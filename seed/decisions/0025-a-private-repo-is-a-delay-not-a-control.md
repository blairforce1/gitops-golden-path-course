# 0025. Assume the clone leaks: a private repo is a delay, not a control, and tenant naming follows scale

- **Status:** accepted
- **Date:** 2026-08-24
- **Deciders:** blairforce1, with Claude Code
- **Supersedes:** none

## Context

Everyone with read access to a config repo, and everyone who used to have it, holds a permanent offline copy, and a clone cannot be revoked. Publishing a config repo is the right answer for a reference implementation and the wrong one for a live fleet (permanent disclosure of the version inventory and, through history, the patch cadence; federation trust conditions published for imitation; tenant names in hostnames becoming a contractual problem; none of it revocable). Over-estimating a leak is also a failure: panic re-keying of things that were never at risk while the real capability sits unrotated. Tenant anonymisation is the one control with a real operational cost: named folders are self-describing under pressure, and anonymisation often moves the disclosure into a runbook rather than removing it, or is theatre where publicly issued certificates already publish the hostnames to Certificate Transparency.

## Decision

Reading the repo must not grant access to anything, tested per file: "nothing" is correct; "they would learn something" sets the anonymisation and patch-cadence requirements; "they could authenticate as something" is a bug. Hardening that applies regardless of visibility: no file is a capability; ciphertext is durable, so rotation is a schedule and a once-plaintext secret is compromised after the fix commit; federation subject conditions pinned to repo, branch and environment with no wildcards; actions pinned by SHA; OIDC over stored secrets; CODEOWNERS carries teams; patch cadence treated as a security control because inventory secrecy is unavailable. What a leak does not give is stated too: no inbound path to a cluster (Flux pulls, the deploy key is read-only and in-cluster), no decryption (CI is keyless), no approval. Tenant naming: names while every reader is inside the same confidentiality boundary as the customer relationship and the list is small enough for a human to be the lookup; IDs when either stops holding, with the display name as an annotation and translation one keystroke away; anonymise the whole identifier chain or none of it, at the boundary (screenshots, tickets, talks), not in the workspace.

## Considered options

- **Rely on repo privacy.** A delay, not a control.
- **Publish the fleet's config repo.** Right for a reference, wrong for a fleet.
- **Anonymise everything always.** Pays the translation cost during the outage, and often leaves the name in metric labels and certificates anyway.

## Consequences

- Easier: the threat model is explicit, so the response to a suspected leak is a rotation runbook rather than a panic; the breach rotation drill rehearses it.
- Harder: the naming decision has to be revisited as the tenant count grows; the failure mode is not choosing wrong but not noticing the crossover.
- Follow-up: where secrets cannot die, the target is reference-not-store, fetched with workload identity, behind a private endpoint, version pinned ([0018](0018-secrets-taxonomy-class-keys-roll-forward.md)).

## Where it is taught or enforced

Rule 5.10 (assume the clone leaks); stages 06, 07 and 21; `appendices/repo-leak-posture.md`; the breach rotation drill.
