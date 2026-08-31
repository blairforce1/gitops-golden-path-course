---
name: onboard-tenant
description: >-
  Onboard a tenant as a replica across the rungs: the tenant leaf per environment, one stamp per (cluster, tenant), the tenant's secret boundary and key, code owners, and the SLO dimension, as one PR with the seven homes of the identifier listed and the isolation proofs. Use when asked to add a tenant, to say what a new tenant needs, or to review a tenant's isolation.
---

# onboard-tenant

A tenant is a replica: parallel, identical by default, divergent on purpose. An environment is a rung. The onboarding never confuses the two: the image pin stays on the environment, so every tenant on a rung receives a promotion; identity lives in the tenant leaf, never in the base.

## 1. Fix the identifier

One string in seven homes: the folder (`apps/tenants/<tenant>/`), the namespace, the `platform.example.com/tenant` label, the stamp name (`<tenant>-<env>`), the status context (`kustomization/<tenant>-<env>/<cluster>`), the metric label, the CODEOWNERS path. Decide it once with the asker: a name while every reader is inside the same confidentiality boundary and the list is small; an ID otherwise, with the display name as an annotation. Confirm the same string in all seven before opening the PR.

## 2. The leaf per rung

```sh
for env in <rungs>; do
  dir=apps/tenants/<tenant>/$env
  mkdir -p $dir && (cd $dir && kustomize create --resources ../../../overlays/$env --namespace <tenant>-$env)
  # the namespace and the tenant label are declared here, never in the base
done
kustomize build apps/tenants/<tenant>/<env> | head -40     # base -> overlay -> leaf, the pin from the overlay
```

Per-tenant patches go in `patches/`, per-tenant variants are components the leaf includes. No per-tenant image pin unless the asker states why; the dogfood tenant is that exception used on purpose.

## 3. The secret boundary

- `.sops.yaml` gains a rule for `apps/tenants/<tenant>/<env>/secrets/.*` per class, recipients = the class key plus the tenant's owning team's keys, placed before the class rule so it matches first.
- Mint the tenant's storage key, write its secret with the tenant's rule (`sops` encrypts with what the rule says), and add the key to the platform-owned composite secret for the storage emulator or the real account.
- Isolation rung, stated in the PR: a container in a shared account is naming, not isolation; an account per tenant with its own key is the boundary; RBAC-scoped identities are the endgame.

## 4. One stamp per (cluster, tenant)

```sh
flux create kustomization <tenant>-<env> --source=GitRepository/flux-system --path=./apps/tenants/<tenant>/<env> \
  --prune=true --wait=true --health-check-timeout=2m --depends-on=infrastructure --decryption-provider=sops --decryption-secret=sops-age \
  --label platform.example.com/tenant=<tenant> --label platform.example.com/release-channel=<channel> \
  --export > clusters/<class>/<cluster>/resources/<tenant>-<env>.kustomization.yaml
```

One stamp per tenant, because a stamp is a blast radius: one tenant's bad image must not be another's change freeze.

## 5. Owners and the SLO dimension

- `CODEOWNERS`: `/apps/tenants/<tenant>/ @<org>/<team>`; `./scripts/path-gate origin/main HEAD` shows the new protected group.
- The SLO rules already group by `exported_namespace`; confirm the tenant's namespace appears in the recording rules once traffic flows, and that the burn-rate alert payload names it.

## 6. The PR and the proofs

`./scripts/pr-open access/<issue>/<tenant> "access(<scope>): onboard tenant <tenant> on <rungs>"` with a body listing the seven homes, the isolation rung chosen, and the proof commands the reviewer runs after merge: the stamps Ready per cluster; `kubectl -n <tenant>-<env> get secret` decrypts only with the tenant's rule; a cross-namespace read from another tenant refused; the other tenants' SLOs unchanged.

## Rules

- Identity leaves the base. One stamp per tenant. The pin stays on the environment.
- The tenant's key is never a recipient on another tenant's path.
- Names or IDs is a decision the PR body states; anonymise the whole chain or none of it.
- The skill never merges.
