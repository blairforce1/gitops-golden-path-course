# 0037. Variants, feature flags and migration overlays: three lifecycles, three homes

- **Status:** accepted
- **Date:** 2026-08-07
- **Deciders:** blairforce1, with Claude Code
- **Supersedes:** none

## Context

A previous fleet kept one `variants/` folder holding three different things, and the mixture was the management pain: true variants (sizing applied to the same components), feature flags (toggled through config, awkwardly tied to versioned releases), and base-change staging (base was never edited directly in a trunk-based repo, so an overlay adjusted config, rolled out progressively, then was folded into base, made a null-op, and finally removed). Flags that were temporary by intent became permanent by accident.

## Decision

Three lifecycles, three homes. **Variants** are permanent named alternatives a stamp selects; the selection outlives releases. **Feature flags** are feature-scoped: born in the release that introduces the feature, default off, promoted channel by channel, then removed. **Migration overlays** are change-scoped: expand/contract for config, with the five-step lifecycle (overlay → progressive rollout → fold into base → null-op → remove references), where the null-op step decouples "base absorbed it" from "references gone" so cleanup need not be atomic. Packaging rule: variant and flag implementations plus a schema with defaults are inside the release artifact; selections live in stamp config in git and float across releases. Flag removal is mechanical: when a release's schema drops a flag, any stamp still setting it fails validation on the pin-move PR, so dead settings cannot survive a pin move and stamps on old releases legitimately keep theirs. Migration overlays carry a created date and CI nags past an age budget.

## Considered options

- **One folder for all three.** The pain itself.
- **Flags in a runtime flag service only.** Some flags are deployment shape, not runtime behaviour; those belong in config.
- **Edit base directly.** Every base edit hits every tenant at once in a trunk-based repo.

## Consequences

- Easier: dead flag settings are caught by CI; migrations cannot stall silently; the rendered-diff report shows the shrinking remainder as a migration rolls out.
- Harder: a schema per release is one more artifact to keep honest.
- Follow-up: most base changes ride the release ladder once base config is versioned inside artifacts ([0036](0036-signed-oci-config-artifacts-are-the-release-destination.md)); migration overlays shrink to config that moves independently of release cadence.

## Where it is taught or enforced

Stage 08 (components), the release-channel stages (flag schema validation at a pin move); the migration overlay lifecycle as quest material.
