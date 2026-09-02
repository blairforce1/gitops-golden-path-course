---
name: promote
argument-hint: "[stamp] [target rung, e.g. app-prod]"
description: >-
  Open a promotion PR that moves a version up one rung on both signatures (the lower rung's green context and a clean SLO window), with the freeze calendar checked, the blast radius rendered, and a body that is a deployment record. Use when asked to promote, to check whether a rung is ready to promote, or to open the promotion PR. Never merges.
---

# promote

A promotion is one pin moved by one PR, on evidence. This skill gathers the evidence, writes the record, and opens the PR. The merge is the human's line, after reading the diff.

## 1. Establish what would move

- The stamp and the target rung are given; the version is what the rung below is serving now, never newer.
- Read the lower rung's pin and the target's pin from the overlays' `kustomization.yaml` (`yq '.images[0].newTag'`), and the lower rung's applied revision:

```sh
kubectl --context <lower-ctx> -n flux-system get kustomization <stamp> -o jsonpath='{.status.lastAppliedRevision}{"\n"}'
./scripts/release-notes <stamp> <target-ctx> <lower-stamp>@<lower-ctx> --first-parent    # what the lower rung has that the target has not
```

Stop if the lower rung's pin equals the target's: there is nothing to promote, say so.

- From stage 14 the lower rung's pin carries a `digest` beside `newTag`. Read the lower rung's running pod and stop if it disagrees with the overlay: the rung is not yet running what its overlay says, so no gate verdict below is about the artifact you would promote.

```sh
kubectl --context <lower-ctx> -n ggp get pod -l app.kubernetes.io/name=app \
  -o jsonpath='{.items[0].status.containerStatuses[0].imageID}'    # ...@sha256:<digest> must equal the overlay's digest
```

## 2. The two signatures

**Convergence.** The commit that put the version on the lower rung wears a green context for that rung's stamp:

```sh
gh api "repos/{owner}/{repo}/commits/<sha>/statuses" --paginate \
  --jq 'sort_by(.created_at) | reverse | unique_by(.context) | .[] | "\(.state)  \(.context)  \(.created_at)"'
```

**Performance.** The lower rung met its SLO over the soak window; no traffic is a FAIL, and a FAIL stops the skill:

```sh
./scripts/slo-gate <lower-cluster> [window]
```

The SLO judge is built at stage 09, so before it this act has one signature. `slo-gate` says which era it is in its first line: `SKIP` (no SLO rule in git yet) means convergence is the only signature, and the body says so under performance; `FAIL` is a verdict and stops the skill. Do not investigate a FAIL, and do not read the course to decide what the era expects: the repo and the gate's own words are the whole source.

Quote both outputs verbatim into the PR body. Never summarise a gate's output into "checks passed".

## 3. The calendar and the reach

```sh
./scripts/freeze-gate --at "$(date -u +%F)" origin/main HEAD    # after the pin edit, before the PR
./scripts/path-gate origin/main HEAD                             # names the protected group the change touches
```

A freeze on the target's paths stops the skill unless the asker names the incident that justifies a `Freeze-override:` trailer; the trailer goes in the body and the reason is quoted. Render the target overlay before and after the edit (`kustomize build`) and confirm the diff is the pin and nothing else.

## 4. The change and the PR

```sh
source ./env.sh
tag=$(yq '.images[0].newTag' apps/overlays/<lower-env>/kustomization.yaml)
digest=$(yq '.images[0].digest // ""' apps/overlays/<lower-env>/kustomization.yaml)   # empty before stage 14
(cd apps/overlays/<target-env> && kustomize edit set image $APP_IMAGE:$tag${digest:+@$digest})
git add apps/overlays/<target-env>
./scripts/pr-open promote/<issue>/<stamp> "promote(<stamp>): app $tag" <<'EOF'
## What is moving
<stamp> on <target rung>: <old tag> -> <new tag>. The pin: one line before stage 14, tag and digest from it.

## Why now
<what the lower rung has served, since when; who asked>

## Evidence
- artifact: <the digest, and that the lower rung's running pod reports the same one>
- convergence: <the green context line, with its timestamp>
- performance: <the slo-gate output, verbatim>
- calendar: <freeze-gate output>; reach: <path-gate output>
- rendered diff: <the one-line diff>

## If it is wrong
`./scripts/pr-revert` on the merge commit; credentials are not involved.

Refs: #<issue>
EOF
```

Then stop. Print the PR URL and the merge line the human runs after the diff: `gh pr merge --merge --delete-branch && git switch main && git pull`, with `gh pr checks --watch --fail-fast && ` in front once the repo has `.github/workflows` (from stage 08 a ruleset refuses a merge before the check reports).

## Rules

- The four sections above are the whole procedure, each command once. No checks beyond them (not the app repo's delta, not the git identity, not the course text); a question the gates do not answer is a gap to state in the body, not something to go and find out.
- Forward only: a pin never moves to an older version by promotion. A rollback is `pr-revert`.
- Never wire automation at the target rung, and never merge.
- A red, absent or no-traffic signature stops the skill; the gate's own words are the reason given.
- One stamp per PR, unless the target is a wave and the wave is the unit; then the body lists every binding that moves.
- Where the promotion also drops a flag or folds a migration overlay, say so in "What is moving".
