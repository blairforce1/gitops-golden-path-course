# 0010. One master per tool, and kubectl never renders

- **Status:** accepted
- **Date:** 2026-08-12
- **Deciders:** blairforce1, with Claude Code
- **Supersedes:** none

## Context

Flux embeds the kustomize Go library, so a local `kustomize build` can diverge from what kustomize-controller renders, and the divergence can be live: a kustomize release with a namespace-propagation regression led the controller to carry a go.mod `replace` pinning its library back to an older version, while the flux CLI's own embedded kustomize moved ahead. The same shape applies to helm (helm-controller embeds `helm/v3`) and to sops and age (kustomize-controller decrypts what the CLI encrypted, using its own embedded libraries, and sops has real cross-version history). kubectl embeds kustomize too, but kubectl's version answers to the Kubernetes ladder, the wrong master for rendering. A workstation's tools drift ahead of all of these by default.

## Decision

Every tool in the chain is pinned to exactly one authority, so no pairwise compatibility matrix exists: flux to the AKS `microsoft.flux` release; kustomize to kustomize-controller's effective library, `replace` directives included; helm to helm-controller's embedded library; sops and age to kustomize-controller's embedded decryption libraries; kubectl to the dev rung of the version ladder. `kubectl apply -k` and `kubectl kustomize` are banned as renderers. `kustomize build` is the canonical overlay renderer; `flux build --dry-run` is the stamp renderer, used where binding-level transforms matter and demoted to advisory whenever the parity script shows the CLI's embedded kustomize diverging from the controller's. Pins live in `clusters/versions.yaml`; the parity scripts derive them mechanically.

## Considered options

- **Latest everything.** The default; the workstation ran ahead of every master on the day the rule was written.
- **Pin to the flux CLI's embedded versions.** The CLI and the controller can disagree; the controller renders in production, so it is the truth.
- **Package-manager installs.** A package manager cannot install a pin; a release binary can. Pinned tools install from release binaries.

## Consequences

- Easier: local render equals cluster render, so golden-file checkpoints and the rendered-diff CI are honest; one graph walk (`check-*-parity`) derives every pin.
- Harder: the chain of authority has to be re-derived when flux moves; Renovate's flux PRs get the parity check as a companion.
- Harder: the dev rung is the client-tooling authority (kubectl tracks dev's Kubernetes, helm tracks dev's flux), and a dev upgrade PR bumps the kubectl pin in the same diff.
- Follow-up: `./scripts/check` is the umbrella gate; cluster-state checkpoints are deliberately not part of it.

## Where it is taught or enforced

Rule 4.1; stage 00 (the toolchain gate), stage 03 (the flux pin), stage 05 (helm), stage 06 (sops/age), stage 07 (the ladder), stage 16 (climbing it); `scripts/check`, `check-kustomize-flux-parity`, `check-helm-flux-parity`, `check-sops-flux-parity`, `check-flux-aks-parity`.
