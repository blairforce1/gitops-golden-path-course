# Act II checkpoint - the fleet exists

[← 07 - Environments & promotion](stage-07.md) · [Walkthrough index](../README.md)

> **Where you are:** the config repo root, on `main`, tree clean and pulled. **Starting state:** stage 07's end state - the three-cluster fleet green (`kind-ggp-local-01`, `kind-ggp-dev-01`, `kind-ggp-prod-01`), `stage-07` tagged. **Before you start:** `source ./env.sh`; the three root age keys under `~/.config/gitops-golden-path/age/` (the rebuild pays exactly those); `gh auth status` green; a stretch where destroying all three clusters is acceptable - the first drill deletes the fleet.

Run this only when stages 05–07 are individually green. It exercises the act as one system: fleet rebuild, promotion up the ladder (platform→dev→prod: folders plus PR discipline plus evidence gates; no controller enforces it), a break on one rung seen from the commit it rode in on, and evidence across clusters. Terminology reminder for the drills: a *stamp* is a Flux `Kustomization` CR. Same rule as Act I: **no stopwatch anywhere**. Timings come from artifacts (commit stamps, per-context status `created_at`, condition transitions).

> **Where this fits:** the checkpoint runs at stage 07, on a three-cluster fleet with no monitoring stack. Act III's checkpoint adds the dashboard-detection drill and the SLO signature, which need stage 09, and reads the four numbers off its own drills, which needs stage 10; drill 3 here detects from statuses alone, which is exactly the point of running it before dashboards exist.

## The drills

### 1. Fleet from nothing - the DR posture at fleet scale

Act I rebuilt one cluster in 77s. The claim to test now: the *fleet* rebuilds from git plus exactly three root keys. Nothing else is remembered.

```sh
source ./env.sh
for name in ggp-local-01 ggp-dev-01 ggp-prod-01; do CLUSTER_NAME=$name ./scripts/cluster-down; done

CLASS=platform CLUSTER_NAME=ggp-local-01 HTTP_PORT=8080 HTTPS_PORT=8443 ./scripts/cluster-up
CLASS=dev      CLUSTER_NAME=ggp-dev-01   HTTP_PORT=8081 HTTPS_PORT=8444 ./scripts/cluster-up
CLASS=prod     CLUSTER_NAME=ggp-prod-01  HTTP_PORT=8082 HTTPS_PORT=8445 ./scripts/cluster-up

./scripts/cluster-sync clusters/platform/local-01 --context kind-ggp-local-01
./scripts/cluster-sync clusters/dev/dev-01 --context kind-ggp-dev-01
./scripts/cluster-sync clusters/prod/prod-01 --context kind-ggp-prod-01

# the surviving IOU: one root key per cluster (stage 06's honest residue)
kubectl --context kind-ggp-local-01 -n flux-system create secret generic sops-age \
  --from-file=age.agekey=$HOME/.config/gitops-golden-path/age/local-01.agekey
kubectl --context kind-ggp-dev-01 -n flux-system create secret generic sops-age \
  --from-file=age.agekey=$HOME/.config/gitops-golden-path/age/dev.agekey
kubectl --context kind-ggp-prod-01 -n flux-system create secret generic sops-age \
  --from-file=age.agekey=$HOME/.config/gitops-golden-path/age/prod.agekey
```

Expect each `cluster-sync` to end with its decrypting stamps `False` and `Secret "sops-age" not found`: the root key cannot exist before `flux install` creates its namespace, so the IOU is paid after the three syncs, and the stamps retry on their interval. That is the residue made visible, not a failure. It is also most of the number you are about to record: a failed reconcile retries at `retryInterval`, which defaults to the stamp's `interval`, 5m here, and nothing tells a stamp that the Secret has arrived. Act III does not remove the residue, but stage 08 sets `retryInterval` on the decrypting stamps, and its checkpoint measures the difference. Now wait for the fleet to converge. Bounded, and loud if it doesn't:

```sh
echo -n "waiting for the fleet to converge (checkpoint-07 passes; the decrypting stamps retry on their interval; up to 10m) "
for i in $(seq 1 40); do ./scripts/checkpoint-07 >/dev/null 2>&1 && break; printf .; sleep 15; done; echo
./scripts/checkpoint-05 \
&& ./scripts/checkpoint-06 \
&& ./scripts/checkpoint-07
```

The timing runs from earliest cluster birth to the last app stamp's first successful reconcile anywhere. Read it from the stamp's `status.history`, not from the Ready condition's `lastTransitionTime`: with `wait: true` the Ready condition flips on every reconcile, so its transition time is the latest 5m tick rather than the first convergence, and the same fleet reads 537s at one minute and 846s five minutes later. A history entry's `firstReconciled` is written once.

```sh
t0=$(for ctx in kind-ggp-local-01 kind-ggp-dev-01 kind-ggp-prod-01; do
  kubectl --context $ctx get ns kube-system -o jsonpath='{.metadata.creationTimestamp}{"\n"}'; done | sort | head -1)
t1=$(for c in kind-ggp-local-01:app-dev kind-ggp-dev-01:app-dev kind-ggp-prod-01:app-prod; do
  kubectl --context ${c%%:*} -n flux-system get kustomization ${c#*:} -o json \
    | jq -r '[.status.history[]? | select(.lastReconciledStatus == "ReconciliationSucceeded") | .firstReconciled] | min'
  done | sort | tail -1)
echo "fleet-from-nothing: $(( $(date -d "$t1" +%s) - $(date -d "$t0" +%s) ))s"
```

One thing the forge will not show you. `main` did not change, so the rebuilt fleet posts nothing: the GitHub provider skips a status identical to the one already on the commit, and the greens on `HEAD` are the destroyed fleet's testimony. `checkpoint-07` counts them and passes on it. The forge's witness to a rebuild is elsewhere: three deploy keys, re-registered under the same titles with new ids (`gh api "repos/{owner}/{repo}/keys"`). The cluster's witness is the one you just read, `status.history`.

**Record: fleet-from-nothing time.** Then tag the boundary you just proved rebuildable - this is the state `act-2-drill` will rebuild to, and the range `git diff act-1..act-2 --stat` reads as the act's change:

```sh
git tag act-2 && git push --tags
```

The tag makes the act one range. Read it once: it is the act's change as git holds it, and nothing in it arrived any other way:

```sh
git diff act-1..act-2 --stat
# → the two spokes and what the platform grew for them, the pins, the secrets machinery,
#   the act's scripts and skills: about 65 files
```

### 2. Promotion - lead time per rung

A fresh release rides the whole ladder. Mint it (dated tag, publish runs ~2–3m):

```sh
source ./env.sh
cd "$APP_DIR" && git pull
TAG="v0.1.1-run$(date +%Y%m%d%H%M%S)"
git tag "$TAG" && git push origin "$TAG"
echo -n "waiting for the registry to have ${TAG#v} (multi-arch build, ~2-3m) "
until docker manifest inspect $APP_IMAGE:${TAG#v} >/dev/null 2>&1; do printf .; sleep 10; done; echo
cd -
```

Rung 1 is dev, by PR, self-merged on green. The dev privilege:

```sh
source ./env.sh
(cd apps/overlays/dev && kustomize edit set image $APP_IMAGE:${TAG#v})
git add apps/overlays/dev
./scripts/pr-open pin/10/dev-${TAG#v} "pin(app-dev): app ${TAG#v}" <<EOF
## What is moving
Dev's app pin to ${TAG#v}.

## Why now
Act II checkpoint drill 2, rung 1: a release enters the ladder.

## Evidence
The image exists on GHCR (polled above).

## If it is wrong
Revert this merge; prod has not moved.

Refs: #10
EOF
```

Read it; when the diff is what the body claims:

```sh
gh pr merge --merge --delete-branch \
&& git switch main \
&& git pull
```

Rung 2 is prod, by PR, on the one signature this act has: convergence, dev's green context. (Act III adds the second, performance: a clean SLO window on the rung below. Its checkpoint requires both. Until then, note honestly that "converged" is the only thing the ladder can ask.)

```sh
gh api "repos/{owner}/{repo}/commits/$(git rev-parse HEAD)/status" \
  --jq '.statuses[] | .context + "  " + .state'   # re-run until app-dev on dev-01 reads success
```

```sh
source ./env.sh
git switch -c promote/10/app-prod \
&& (cd apps/overlays/prod && kustomize edit set image $APP_IMAGE:${TAG#v})
git add apps/overlays/prod
git commit -m "promote(app-prod): app ${TAG#v}" && git push -u origin promote/10/app-prod
gh pr create --title "promote(app-prod): app ${TAG#v}" \
  --body "Normally a comprehensive description goes here: what's moving, why now, and the evidence - dev's green context on the source commit.

Refs: #10"
gh pr diff             # one pin move - the whole promotion
```

Read it; when the diff is what the body claims:

```sh
gh pr merge --merge --delete-branch \
&& git switch main \
&& git pull
```

Timings, per rung, from each rung's own commit and its cluster's context. Find each commit **by its subject**, which the [commit convention](../appendices/commit-convention.md) made a field rather than prose. `rung-time` takes the subject and resolves it through `scripts/commit-by-subject`, the lookup the drills and gates share:

```sh
./scripts/rung-time "pin(app-dev): app ${TAG#v}" \
  kustomization/app-dev/dev-01 kind-ggp-dev-01 app-dev
# → fe84cb1  kustomization/app-dev/dev-01: 38s

./scripts/rung-time "promote(app-prod): app ${TAG#v}" \
  kustomization/app-prod/prod-01 kind-ggp-prod-01 app-prod
# → 08dbf87  kustomization/app-prod/prod-01: 9s
```

> `commit-by-subject` matches the subject field exactly, first-parent, not `--grep`. A substring search would find the *revert* of a break rather than the break, since `git revert` quotes the subject it undoes, and an unanchored version match finds `0.1.10` when you asked for `0.1.1`. It is awk, so no `grep.patternType` setting can reinterpret it, and it ignores the ` (#N)` GitHub appends to a merge commit's subject.

Two details that stop this measuring the wrong thing. **Both rungs are found by their commit message, never by `HEAD`**: any commit landing after your merge (a teammate's, a bot's, a docs fix) silently becomes `HEAD` and you end up timing *its* convergence instead, which produces a plausible number for the wrong event. And **full status contexts, not prefixes**: two clusters run `app-dev`, so the declared suffix from stage 07 is what pins each timing to its own cluster.

**A measurement trap worth more than the number it protects.** Stage 04 taught that a commit can wear a **red the cluster already had**; here is its mirror, and it only shows up when you time things: a commit can wear a **green that is not a success**. A commit status has two states, and Flux's provider derives them from an event's *severity*: an error posts a failure and every other event posts a success, with the event's reason as the description. Most of those events are not "reconciliation succeeded". When a fetch lands, a stamp with `dependsOn` reconciles the new revision before its dependencies have, records "dependency not ready" and retries later; that is an info event, so it posts as **success**, on the right commit, seconds after the merge, before anything is applied. A rollout interrupted by the next commit does the same: "health checks canceled" is info too. Observed: a prod promotion merged at 21:20:27 wore `success  dependency not ready` at 21:20:31, its ReplicaSet was created at 21:20:42, and `success  reconciliation succeeded` arrived at 21:21:02. Measured by state alone that promotion took **4 seconds**; it actually took **35**. The guard above is the fix: wait for `lastAppliedRevision` to name your revision, then read the status whose description is `reconciliation succeeded`, which is what `rung-time` does. And the general rule is the same one this whole act keeps teaching: **ask the cluster what it applied; ask git what you asked for; never let a green stand in for either.**

**What you will see.** The dev line prints a `note:` before its number. Both commits land on `main`, so by the time you measure, dev has applied the prod promotion too; `rung-time` sees the pin is an ancestor of what dev is on, and reads the pin's status after the fact rather than waiting for a revision that will not come round again. And the two numbers differ by tens of seconds for no reason the rungs control. Stage 03 measured why: a merge waits for the source's next fetch, anywhere up to its 1m interval, and only then does the rollout start. Observed: dev 38s and prod 9s; the clusters' events split each into its parts (`kubectl --context kind-ggp-prod-01 -n flux-system get events --field-selector involvedObject.name=app-prod`): the fetch landed 33s after dev's merge and 4s after prod's, and both rollouts took 5s. Record the whole, because the whole is what the ladder makes a release wait; the part a rung owns is the rollout.

**Record: dev rung and prod rung lead times.**

### 3. A break on one rung - seen from the commit, not from a dashboard

Stage 04 broke one stamp on one cluster and read the failure off the commit. The fleet version of that question is *which* rung, and the only fleet-wide view this act has is the commit's own statuses: one context per stamp per cluster, the suffixes stage 07 declared. That is enough to answer it, and noticing how much it takes is Act III's motivation.

Break prod, by PR, with an image that does not exist. Everything else about the change is well-formed: it parses, it renders, it passes review. So the failure is a *health* failure, and it lands only where the render changed:

```sh
source ./env.sh
git switch -c break/10/app-prod \
&& (cd apps/overlays/prod && kustomize edit set image $APP_IMAGE:0.0.0-absent)
git add apps/overlays/prod
git commit -m "break(app-prod): absent image" && git push -u origin break/10/app-prod
gh pr create --title "break(app-prod): absent image" \
  --body "Checkpoint drill 3: a health failure scoped to one rung. Reverted by the next PR.

Refs: #10"
gh pr diff             # the deliberate break, in plain sight before you merge it
```

Read it; when the diff is what the body claims:

```sh
gh pr merge --merge --delete-branch \
&& git switch main \
&& git pull
```

Watch the statuses on the merge commit until the prod context goes red. The dev contexts stay green, because their render did not change. Note the order and the timestamps; they are the measurement:

> Known issue on the pinned 2.8.8 bundle: no failure posts a commit status ([notification-controller#1373](https://github.com/fluxcd/notification-controller/issues/1373), fixed in Flux 2.9 by [#1317](https://github.com/fluxcd/notification-controller/pull/1317)), so until the pin moves `app-prod`'s context sits **absent** on the break commit rather than red, the verdict held in the stamp's conditions and events. From 2.9 on the queries below read as written.

```sh
sha=$(./scripts/commit-by-subject "break(app-prod): absent image")
gh api "repos/{owner}/{repo}/commits/$sha/statuses" \
  --jq '.[] | .created_at + "  " + .context + "  " + .state + "  " + .description' | tac
```

Break → confirmed red, from artifacts: the commit's own timestamp and the first `failure` status on the prod context.

```sh
t0=$(git show -s --format=%cI "$sha")
t1=$(gh api "repos/{owner}/{repo}/commits/$sha/statuses" \
  --jq '[.[] | select(.context == "kustomization/app-prod/prod-01" and .state == "failure")] | last | .created_at')
echo "break -> confirmed red: $(( $(date -d "$t1" +%s) - $(date -d "$t0" +%s) ))s   (stamp gave up after its health timeout)"
```

On the 2.8.8 pin `t1` comes back empty, because the failure never posts, and `date -d ""` is midnight, so the subtraction goes negative. The verdict is then the stamp's own. Watch `flux get kustomizations --context kind-ggp-prod-01` instead of the statuses: `app-prod` sits at `Ready=Unknown` for the whole health timeout (3m) before it goes `False`. Its first `HealthCheckFailed` event is the moment prod gave up on the rollout, and the same subtraction applies:

```sh
t1=$(kubectl --context kind-ggp-prod-01 -n flux-system get events \
  --field-selector involvedObject.name=app-prod,reason=HealthCheckFailed -o json \
  | jq -r '[.items[].firstTimestamp] | min')
echo "break -> confirmed red: $(( $(date -d "$t1" +%s) - $(date -d "$t0" +%s) ))s   (from the stamp's event)"
```

Restore by PR. `git revert` writes the subject; do not rewrite it, it is the durable link to what it undoes:

```sh
./scripts/pr-revert "$sha" "Checkpoint drill 3: restore prod after the deliberate break."
```

Read it; when the diff is what the body claims:

```sh
gh pr merge --merge --delete-branch \
&& git switch main \
&& git pull
echo -n "waiting for prod to come back (checkpoint-07 passes; the revert rides the source interval, then a rollout; up to 5m) "
for i in $(seq 1 20); do ./scripts/checkpoint-07 >/dev/null 2>&1 && break; printf .; sleep 15; done; echo
./scripts/checkpoint-07
```

**Record: break → confirmed red.** And record the thing the number hides: you knew *which* cluster only because you were looking at that commit. A break that rides in on someone else's commit, or on a Renovate PR, or that starts as a slow degradation, has no commit you are watching. The fleet needs a view that is not per-commit. That view is stage 09; the drill that measures it is Act III's.

### 4. The evidence question - across clusters

The auditor, again, harder: *"Between the break and the restore, what was prod actually running, who fixed it, and how do you know dev was unaffected?"* Durable artifacts only: memory and terminal scrollback are off-limits.

One command, because a dossier is a deliverable and not a pile of raw query output:

```sh
./scripts/evidence 'break(app-prod): '
```

```
THE CHANGE
----------
  commit         e99aba0  break(app-prod): absent image (#97)
  author         <you> <you@example.com>
  committed      2026-09-01T10:35:43+01:00
  files          apps/overlays/prod/kustomization.yaml
  blast radius   app-prod on prod-01  (from the status context that never posted: it did on the parent commit)

WHO TOUCHED THIS PATH AFTERWARDS
--------------------------------
  da56930   2026-09-01T10:48:20+01:00  Revert "break(app-prod): absent image (#97)" (#98)  <you>
  e99aba0   2026-09-01T10:35:43+01:00  break(app-prod): absent image (#97)                <you>

WHAT THE FLEET SAID, IN ORDER
-----------------------------
  ...  (every other context, in the order the clusters fetched: success, reconciliation succeeded)

  success: 14
  silent: 1   kustomization/app-prod/prod-01  (posted on the parent commit, never on this one)
  (the /status endpoint shows only this last line - the latest per context. The
   sequence above needs /statuses, and the sequence is what shows a green whose
   description is not 'reconciliation succeeded'.)

WHAT THAT CLUSTER ACTUALLY APPLIED
----------------------------------
  now running    da56930  Revert "break(app-prod): absent image (#97)" (#98)
  verdict        this commit is an ancestor of what the cluster runs now
                 (true after a revert too - the revert is also an ancestor. What the
                  cluster served DURING the failure is the status sequence above.)
  gave up        2026-09-01T09:39:02Z  (first HealthCheckFailed event; the stamp's own verdict)

THE ANSWER, IN ENGLISH
----------------------
  <you> changed app-prod on 2026-09-01.
  The fleet reconciled that commit everywhere; only prod-01 never posted
  on it, because only its render changed and its stamp never converged (on Flux
  2.8.x a failure does not post, so the silence is the red). Reconcile scope is
  the repo, change scope is the paths the commit touched.
  The failure was a health check, not an apply error - which is the whole point:
  the stamp failed and the workload did not. The cluster kept serving the last
  revision that passed, so the artifacts prove a negative (the bad version never
  ran) without anyone having been watching.
```

Note the second line of the dossier and what produced it. **Nothing was told which cluster to look at**: the script read the status context that went red, `kustomization/app-prod/prod-01`, and split the stamp and cluster straight out of it. On the 2.8.8 pin nothing goes red, so it reads the context that went *silent* instead, posted on the parent commit and never on this one, and the dossier says so (`from the status context that never posted`, `silent: 1`); the stamp's own `HealthCheckFailed` event supplies the verdict while it lasts. Same string, same split. That is the [identifier alignment rule](../appendices/repo-leak-posture.md) collecting: one string names the stamp, the namespace, the label, the metric, the commit scope *and* the status context, so a tool handed a red context already knows which file to open.

Now read what the script actually did, because the lesson is the queries and not the existence of a script. Each is a line or two against an artifact that outlives everyone who was on the call, and each answers one question. Run them one at a time:

**Who touched the path, and when.** Git, first-parent, so the merges and not the branch commits beneath them:

```sh
sha=$(./scripts/commit-by-subject "break(app-prod): absent image")   # exact subject, so the revert cannot win
git log --first-parent --format='%h  %cI  %s  (%an)' "$sha^..HEAD" -- apps/overlays/prod
# → da56930  2026-09-01T10:48:20+01:00  Revert "break(app-prod): absent image (#97)" (#98)  (<you>)
# → e99aba0  2026-09-01T10:35:43+01:00  break(app-prod): absent image (#97)  (<you>)
```

**Which clusters reported, and what.** The forge, one line per context, the latest post per context:

```sh
gh api "repos/{owner}/{repo}/commits/$sha/status" \
  --jq '.statuses[] | .context + "  " + .state'
# → kustomization/infrastructure/prod-01  success
# → kustomization/cluster-secrets/prod-01  success
# → (six more, all success; no kustomization/app-prod/prod-01 line at all)
```

Eight contexts, all `success`, and the ninth, `kustomization/app-prod/prod-01`, is missing. On the 2.8.8 pin the absence *is* the red: the stamp never converged, so it never posted, and this pin posts no failure event at all. From 2.9 on the line is there and reads `failure`. The reading is the same either way: every cluster reconciled this commit, and only prod's app stamp has anything against it.

**The sequence.** The same statuses with every post and its time, oldest first:

```sh
gh api "repos/{owner}/{repo}/commits/$sha/statuses" \
  --jq '.[] | .created_at + "  " + .context + "  " + .state + "  " + .description' | tac
```

What the summary above collapses, this keeps: the order the clusters fetched (prod, local, dev, seconds apart) and, from 2.9 on, where prod's failure fell among the greens. It is also where a green that is not a success shows up (drill 2).

**What prod ran, before, during and after.** The cluster: the stamp's `status.history`, one entry per render, keyed by the digest of what was applied:

```sh
kubectl --context kind-ggp-prod-01 -n flux-system get kustomization app-prod -o json \
  | jq -r '.status.history[] | .firstReconciled + "  " + .lastReconciled + "  x" + (.totalReconciliations|tostring)
           + "  " + .lastReconciledStatus + "  " + .metadata.revision[0:17]'
# → 2026-09-01T08:41:11Z  2026-09-01T10:09:01Z  x19  ReconciliationSucceeded  main@sha1:06dc4f1
# → 2026-09-01T09:39:02Z  2026-09-01T09:46:07Z  x2  HealthCheckFailed  main@sha1:e99aba0
# → 2026-09-01T08:30:21Z  2026-09-01T08:39:01Z  x3  ReconciliationSucceeded  main@sha1:fe84cb1
```

Read the second answer once more: **all three clusters reconciled this commit; only prod changed.** A shared source means every cluster fetches every commit, so "reconciled" is not evidence of "affected" ([rule 5.5](../rules.md#55-reconcile-scope-is-not-change-scope)). The paths the commit touched decide that, and this one touched only `apps/overlays/prod/`. Had it touched `base/`, the same one-line diff would have reached all three with no promotion at all: the ladder gates what lives on a rung, and nothing else. That asymmetry is the argument for path-scoped review (CODEOWNERS on `base/`, `clusters/`, prod overlays, `infrastructure/`, the gates themselves). See [stage 07 §4](stage-07.md#4-promotion-is-a-pr-that-moves-a-pin), where the paths and their reasons are listed; stage 21 wires it.

The last answer is the sharpest in the course so far. Read the history: the break's render was reconciled twice and failed both times, so `lastAppliedRevision` never named it. The render prod runs now carries the digest it had before the break, first reconciled at the promotion; the promotion, the revert and everything since share that one line, because the revert restored the same bytes, and the line's revision names the latest commit to produce that render, not the first. Health gating means the broken change never became prod's truth, and the artifact proves a negative ("the bad version never ran") without anyone having watched.

## AI enhancement

**How.** One skill, `run-drill`, running drill 1 again as one script and stopping where the human's line is: the tag and the closing of the item. The other drills are not repeated: the skills they use have their second outings inside the stages (`promote` at stages 07 and 09, `fleet-triage` at 04 and 09) and in Act VI's audit drill (`audit-evidence`). Run it from the config repo in Claude Code, on `main` with a clean tree.

**Drill 1, the rebuild.** `run-drill` runs `scripts/act-2-drill`, the fleet-from-nothing rebuild as one script: three clusters down and up, `cluster-sync` each, the three root keys paid, the checkpoints, and the number from artifacts. It runs the script detached and reads its log, since nine minutes outlives a tool call, and writes the pack on this checkpoint's work item, `#10`: the number with its source, the refusals, the findings. Be on `main` with a clean tree; the script refuses otherwise. Bare, it prints what it would destroy and refuses:

```
/run-drill rebuild act-2
```

Then, having read the blast radius, the run. Nine minutes on the measured fleet:

```
/run-drill rebuild act-2 --yes
```

**Why.** A drill's value is the evidence pack, and the pack is where hand-run drills go thin: the number gets typed from memory. The script gives the verdicts and the number; the skill sequences the run and writes the pack.

**Where.** After the checkpoint has been run by hand once, and before its work item is closed.

**Verify.** What the rebuild leaves. The pack: the number on the work item agrees with the table below:

```sh
gh issue view 10 --comments | grep -n 'fleet-from-nothing'
```

And no skill merged anything: every merge in `git log --first-parent --merges` since the tag is one you ran.

## Pass criteria

- [ ] All four drills completed; numbers recorded below.
- [ ] Zero `kubectl apply`/`edit`/`scale` in drills 2–4; prod touched only by PR.
- [ ] The prod rung merged on dev's green context, the convergence signature. (Act III adds the second.)
- [ ] The evidence question answered from durable artifacts alone, per cluster.
- [ ] The config repo tagged `act-2` (drill 1 did it), the checkpoint's work item closed and the milestone with it ([using the course §5](../using-the-course.md#5-tags-at-every-boundary)):

```sh
gh issue close 10 --comment "act-2 tagged" && gh api -X PATCH "repos/{owner}/{repo}/milestones/2" -f state=closed
```

| Measure | Value | Date |
|---|---|---|
| Fleet-from-nothing | – | – |
| Dev rung (merge → green on dev-01) | – | – |
| Prod rung (merge → green on prod-01) | – | – |
| Break → confirmed red (statuses, or the stamp's event on 2.8.8) | – | – |

Reference values from a three-cluster kind fleet: fleet-from-nothing ≈535s, most of it the decrypting stamps' retry interval after the root keys land; dev rung ≈40s and prod rung ≈10s, each a 5s rollout plus wherever in the source's minute the merge fell; break → confirmed red ≈200s, of which 180s is the health timeout. Yours come from artifacts, not from this sentence.

## After the checkpoint

- Found a broken step? Fixes to the walkthrough are PRs against the course repo.
- **What "scratch" meant here:** every kind cluster. What survived: git, and three root keys on your workstation. Act III does not change that definition; Act VII is the first act that does. What Act III changes is the wait: the minutes the decrypting stamps spent retrying after the keys landed are a `retryInterval` away, stage 08's first line.

---

**Next:** [08 - Dependencies & health](../act-3/stage-08.md)
