---
name: fleet-triage
argument-hint: "[kustomization/<stamp>/<cluster> | the alert's identifiers | "why hasn't my change appeared"]"
description: >-
  Diagnose a red or stuck stamp by the four-layer ladder (fetch, build, apply, health) from the identifier in an alert or status, read what the cluster applied and what the fleet said, and recommend the fix as a PR. Use when a change has not appeared, a stamp is not Ready, a commit wears a red, or a dashboard row is red. Reads only; never applies, edits, scales or suspends.
---

# fleet-triage

Start from the identifier. A status context is `kustomization/<stamp>/<cluster>`; an alert carries `cluster`, `namespace` and the stamp name. Split it; that names the binding file, the overlay and the kube context with no lookup.

## 1. Which layer failed: the ladder, top down, stop at the first failure

| Layer | The question | Read |
|---|---|---|
| fetch | did the source get the commit | `flux --context <ctx> get sources git`; the source's `lastHandledReconcileAt` against the merge time; the interval is the floor unless a receiver poked it |
| build | did it render | `flux --context <ctx> get kustomizations`; `flux --context <ctx> events --for Kustomization/<stamp>`; reproduce locally with `kustomize build <path>` at the same commit |
| apply | did the API server accept it | the events: server-side apply conflicts, immutable fields, webhook and admission refusals |
| health | did the workload become ready | `flux --context <ctx> tree kustomization <stamp>`; `kubectl --context <ctx> rollout status deploy/<name>`; `kubectl describe` on the failing pod; `./scripts/slo-watch <cluster>` for the user-facing fact |

Quote the reason string verbatim from the condition or the event. Do not paraphrase it.

## 2. The two facts the ladder is judged against

```sh
kubectl --context <ctx> -n flux-system get kustomization <stamp> -o jsonpath='{.status.lastAppliedRevision}{"\n"}'
gh api "repos/{owner}/{repo}/commits/<sha>/statuses" --paginate \
  --jq 'sort_by(.created_at) | .[] | "\(.created_at)  \(.state)  \(.context)  \(.description // "")"'
./scripts/detect-time <stamp> <ctx> [break-subject]       # when the question is "since when"
```

Read them together: a green status is any non-error event, so read its description (`dependency not ready` and `health checks canceled` are both green); the applied revision says what runs; the sequence says when each verdict was posted. On Flux 2.8.x no failure posts at all, so a context that posted on the parent commit and not on this one is the red. Before stage 09 `detect-time` says `SKIP`, there being no hub; "since when" then comes from the stamp's `status.history` (the first reconcile of the failing render), its events while they last, and the kustomize-controller log after that.

## 3. Three things that look like failures and are not

- **The dependency cascade.** On every new revision, each stamp with `dependsOn` reports Ready=False with `DependencyNotReady` while its dependency reconciles, so the dashboard reds fleet-wide for one scrape. The discriminator is duration, not colour.
- **Unknown is part of a failure, not a pause.** A stamp under `wait: true` with a short `retryInterval` spends each attempt at Ready=Unknown (`Reconciliation in progress`, the health timeout) and only the gap between attempts at Ready=False. A stamp out of Ready for longer than its health timeout is failing whichever value it shows now; the reason is on the last `HealthCheckFailed` event.
- **A green that is not a success.** The provider maps event severity to state, so an info event posts as `success` whatever it says. Read the description; only `reconciliation succeeded` is the verdict, and `lastAppliedRevision` is the fact.
- **Suspended is not stuck.** `spec.suspend: true` on the stamp means nothing reconciles until a resume; find who set it in the API audit log, if enabled, and treat the resume as a change.

## 4. The answer

State: the layer, the reason string, the evidence lines, the file to open (named from the identifier), and the fix as a PR: `./scripts/pr-revert` for a bad change, a pin move for a bad version, a config change for a bad value. Never a `kubectl apply`, `edit`, `scale` or `flux suspend` as the fix.

## Rules

- Read only. This skill changes nothing on a cluster or in git.
- Ready is a resource fact; if the ask is "is it working", answer from the SLI, not from Ready.
- "Since when" comes from timestamps in the artifacts, never from memory.
- If the identifier does not name the file to open, report that as a finding about the naming.
