# 0018. Secrets: SOPS and age in git, class-scoped keys, per-principal recipients, reference what cannot die, and roll forward

- **Status:** accepted
- **Date:** 2026-08-14
- **Deciders:** blairforce1, with Claude Code
- **Supersedes:** none

## Context

Secrets are the wall most GitOps material avoids. The choices (SOPS, sealed-secrets, external-secrets) paralyse teams; key custody on one laptop is a trap for a team; git history keeps every old ciphertext forever; and a secret differs from every other artifact in the repo in one way that makes rollback dangerous: it is a pointer to state the repo does not own, so a revert restores an address with nothing behind it and reconciles green. A DR move PR must be self-sufficient, so per-cluster keys would force mid-incident re-encryption. Not every secret can be dissolved by federation: third-party keys (SaaS APIs, SMTP, a forge token for posting commit statuses) have no federation on offer.

## Decision

Secrets divide into **dissolvable** (cloud credentials, replaced outright by a federation handshake) and **irreducible** (held well instead of wished away). The ladder for irreducible secrets: encrypted in git with SOPS and age first; referenced, not stored, later (an `ExternalSecret` pointer to a vault, version pinned in the reference where reproducibility matters). Keys are **class-scoped**, one per class, accepting the wider blast radius within a class so a DR move needs no re-encryption. For teams, `.sops.yaml` lists per-principal recipients (the class cluster key plus each authorised human's key); `sops updatekeys` re-wraps on roster change; offboarding is remove-recipient-then-rotate; the root key has a home that outlives a laptop. Three teeth: rotating an irreducible secret means **revoking** the old value at the provider, never just committing a new one; **for secrets, roll forward, never back**, a revert carries code back and credentials forward in one commit and `revert-gate` refuses the alternative; and **assume the clone leaks**, so reading the repo must not grant access to anything ([0025](0025-a-private-repo-is-a-delay-not-a-control.md)). Something always remains (a root key per class locally, a managed identity in cloud); the goal is one well-guarded root credential per class, not zero.

## Considered options

- **sealed-secrets.** Cluster-bound keys make DR-as-rebuild depend on backing up the controller's key; the ciphertext is not portable across clusters.
- **external-secrets from day one.** Needs a vault and an identity to reach it, which is the chicken-and-egg that makes teams abandon vaults; it is the second rung, not the first.
- **Per-cluster keys.** Tighter blast radius, and a DR move becomes a re-encryption under time pressure.
- **A shared team key.** Bus factor 1 and no offboarding story.
- **One pin file per environment for vault versions.** Could only reach manifests through substitution, breaking render parity; pins live with the references they pin.

## Consequences

- Easier: teammates encrypt new secrets with zero key exchange (recipients are public keys in git); the `secrets/` folder is the countable debt and its endgame is conversion; rotation in a vault needs no commit.
- Harder: rotation is two-phase (overlap, then retire) and two rotations (key and values, because history keeps ciphertext); every old value kept working past the overlap window is an unrevoked credential.
- Harder: pods keep a rotated value until restarted when secrets are committed as plain encrypted resources; Reloader recovers rollout-on-change, opt-in per workload.
- Follow-up: the forge token that posts commit statuses is the standing specimen of an irreducible secret and migrates from sops file to `ExternalSecret` when the vault arrives.

## Where it is taught or enforced

Rule 5.10; stage 06 (SOPS, the taxonomy, key custody boundary), stages 17–20 (rotation, team keys, Reloader, roll forward), stage 31 (referenced, not stored); `scripts/revert-gate`, `scripts/checkpoint-06`, `.sops.yaml`; `appendices/repo-leak-posture.md`.
