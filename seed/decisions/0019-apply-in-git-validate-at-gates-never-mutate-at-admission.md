# 0019. Standards are applied in git and validated at gates; admission never mutates

- **Status:** accepted
- **Date:** 2026-08-10
- **Deciders:** blairforce1, with Claude Code
- **Supersedes:** none

## Context

A workload baseline (non-root, seccomp, dropped capabilities, read-only rootfs, requests and limits, immutable tags, named ports) has to be applied to every workload and proven at every boundary. Admission controllers can *mutate* a pod to conform, which is convenient and makes the cluster diverge from what git shows: the reviewer approved one thing, the cluster runs another, and the rendered-diff and golden-file checks are checking the wrong artifact.

## Decision

Standards are applied **in git** as a Kustomize component (`components/workload-baseline`) that an overlay adopts with one line, then **validated at every gate**: conftest over rendered output in CI (`policy-gate`), Pod Security Admission `restricted` labels on namespaces, Kyverno validation at admission. Admission **mutation is banned**. Git must tell the truth; gates verify it. Paired controls, one preventive in the repo and one detective at the cluster, are the pattern for every standard that follows. `imagePullPolicy` discipline is the real rule behind it: never `:latest`, so immutable tags make `IfNotPresent` safe. `nodeSelector` is carried in the baseline but only real when node pools exist, and the baseline says so.

## Considered options

- **Mutating admission (Kyverno mutate, PSP-style defaults).** Convenient; makes the cluster diverge from git and hides the standard from review.
- **Validation only at admission.** Late: the PR merged, the reconcile failed, and the fix is another PR; CI on rendered output catches it before merge.
- **Validation only in CI.** Anything reaching the cluster by another path is unchecked; the admission layer is the backstop for that.

## Consequences

- Easier: adopting the baseline is one overlay line; a violation is caught in CI and again at admission; the render a reviewer reads is the render that runs.
- Harder: some workloads break under a hardened baseline and need real fixes, not exemptions; policy exceptions exist as `PolicyException` resources with a mandatory expiry and a CI age nag.
- Follow-up: the config-testing ladder is schema (kubeconform) → golden files → policy assertions, and the golden files are nearly free because the rendered-diff job already renders every entry point.

## Where it is taught or enforced

Rule 5.6; stage 08 (the component and `policy-gate`), stage 23 (PSA labels per tenant), stage 30 (Kyverno validate, exceptions with expiry); `scripts/policy-gate`, `policy/`.
