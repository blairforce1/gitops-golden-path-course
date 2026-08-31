# 0036. Signed OCI config artifacts are the release destination; channel tags serve the fast channels only

- **Status:** accepted
- **Date:** 2026-08-26
- **Deciders:** blairforce1, with Claude Code
- **Supersedes:** none

## Context

Git-path reconciliation has weaknesses a fleet feels: convention-only immutability, a PR-generating action for every pin move, and no signature on the config a cluster applies even when its images are signed. The verification spine (keyless signing, SBOM attestations, `verifyImages`) exists for images; config deserves the same treatment. Pre-rendering and per-tenant artifact generation exist in the ecosystem, but an in-cluster generator has no signature gating, so it cannot be the spine. `postBuild` substitution resolves after verification, a boundary that has to be named.

## Decision

The destination is CI-built, signed, per-cluster config artifacts: `flux push artifact` at cut time, cosign signature, `OCIRepository.spec.verify` at the cluster, so config gets the supply-chain treatment and not just images. Pins stay in git and stay reviewable, guarded by owners. Fast channels advance by promotion-by-retag (CI moves a channel tag only when soak windows and health checks pass: automated judgement, not just automated movement); GA advances by explicit PR in waves ([0016](0016-release-channels-as-a-label-ascent-judged-where-members-exist.md)). Immutability is registry-enforced. The path is hand-build-then-absorb: folder pins first, so their weaknesses are experienced rather than asserted, then the conversion. The interim allowlist on substitution is the honest concession while nothing is signed; once `verify` exists the concession has a measurable cost, and the conversion is drilled by a binding-move rebind: alignment gate red, CI re-bakes and re-signs, green.

## Considered options

- **Git paths forever.** No signature on config; immutability by convention.
- **An in-cluster artifact generator as the spine.** No signature gating; one honest paragraph, not the destination.
- **Pre-render everything with `flux build`.** A recurring render-time cost, priced and kept as an option, not the mechanism.

## Consequences

- Easier: unsigned config is rejected at the cluster, demonstrably; a release is an immutable artifact with a version, not a folder.
- Harder: a build step between git and the cluster, which the rendered-diff and golden-file gates must cover.
- Follow-up: the OCI quest after Act VII carries the conversion; `flux push` and cosign join the toolbox.

## Where it is taught or enforced

Stage 30 (the verification spine), stages 28 and 29 (channels and waves on folder pins), the OCI-published config artifacts quest (after Act VII).
