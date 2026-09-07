# Act III checkpoint - the fleet, end to end

[← 10 - The four numbers (DORA, per cluster and per tenant)](stage-10.md) · [Walkthrough index](../README.md)

> **Where you are:** the config repo root, on `main`, tree clean and pulled. **Starting state:** stage 10's end state: the fleet green with the hub live, `dora` run once, `stage-10` tagged. **Before you start:** `source ./env.sh`; the three root age keys under `~/.config/gitops-golden-path/age/` (the rebuild pays exactly those); `gh auth status` green; a stretch where destroying all three clusters is acceptable - the first drill deletes the fleet.

Run this only when stages 08–10 are individually green. It exercises the act as one system: fleet rebuild, promotion up the ladder (platform→dev→prod: folders plus PR discipline plus evidence gates; no controller enforces it), detection from the dashboard, evidence across clusters, and the four numbers read off the drills themselves. Terminology reminder for the drills: a *stamp* is a Flux `Kustomization` CR. Same rule as Act I: **no stopwatch anywhere**: timings come from artifacts (commit stamps, per-context status `created_at`, condition transitions, metric sample timestamps).

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

git pull   # nothing was committed - but be on the merge the clusters are syncing
```

**The hub address survives the rebuild.** `cluster-facts` names the hub by the platform node's *container name*, and the rebuilt node kept its name even though its IP changed - so the spokes' remote-write reconnects on its own, and the rebuild stays what the doctrine promised: zero commits. This is stage 09 step 2's choice paying out; notice how the drill would read if the facts pinned an IP instead. (If yours do, because your environment doesn't resolve container names: this is where it bites. `./scripts/refresh-hub-address`, read the three-line diff, then PR and merge it before the wait below.)

Nudge the fleet rather than waiting out intervals:

```sh
for ctx in kind-ggp-local-01 kind-ggp-dev-01 kind-ggp-prod-01; do
  flux reconcile kustomization flux-system --with-source --context $ctx
done
```

Now wait for the fleet to converge, bounded, and loud if it doesn't (the monitoring stack is a heavy pull; 10 minutes is generous, not typical):

```sh
echo -n "waiting for the fleet to converge (checkpoint-09 passes; the monitoring stack is a heavy pull; up to 10m) "
for i in $(seq 1 40); do ./scripts/checkpoint-09 >/dev/null 2>&1 && break; printf .; sleep 15; done; echo
./scripts/checkpoint-07 \
&& ./scripts/checkpoint-08 \
&& ./scripts/checkpoint-09
```

The timing runs from earliest cluster birth to the last app stamp's first successful reconcile anywhere: the same three stamps Act II timed, so the two numbers compare, and the monitoring stack's pull is in the wait above rather than in the number. Read it from the stamp's `status.history`, not from the Ready condition's `lastTransitionTime`: with `wait: true` the Ready condition flips on every reconcile, so its transition time is the latest 5m tick rather than the first convergence, and the same fleet reads 537s at one minute and 846s five minutes later. A history entry's `firstReconciled` is written once.

```sh
t0=$(for ctx in kind-ggp-local-01 kind-ggp-dev-01 kind-ggp-prod-01; do
  kubectl --context $ctx get ns kube-system -o jsonpath='{.metadata.creationTimestamp}{"\n"}'; done | sort | head -1)
t1=$(for c in kind-ggp-local-01:app-dev kind-ggp-dev-01:app-dev kind-ggp-prod-01:app-prod; do
  kubectl --context ${c%%:*} -n flux-system get kustomization ${c#*:} -o json \
    | jq -r '[.status.history[]? | select(.lastReconciledStatus == "ReconciliationSucceeded") | .firstReconciled] | min'
  done | sort | tail -1)
echo "fleet-from-nothing: $(( $(date -d "$t1" +%s) - $(date -d "$t0" +%s) ))s"
```

As at Act II, the forge shows nothing: `main` did not change, the GitHub provider skips a status identical to the one already on the commit, and the greens on `HEAD` are the destroyed fleet's testimony. The witnesses are the three deploy keys `cluster-sync` re-registered (`gh api "repos/{owner}/{repo}/keys"`) and the `status.history` you just read.

**Record: fleet-from-nothing time**, and put it beside Act II's. This fleet carries the monitoring stack, a heavier pull, and yet expect the number to fall: Act II's rebuild spent most of its minutes with the decrypting stamps waiting out their 5m `interval` after the root keys landed, and stage 08's `retryInterval: 30s` is what that wait became. `scripts/act-3-drill` is this drill as one script, for the next time you need the number; the AI enhancement below runs it.

### 2. Promotion - lead time per rung

**First, traffic.** This drill's prod gate reads dev's error budget, and an SLO over zero requests is no evidence at all. Drill 1 rebuilt the fleet, so nothing is exercising the app. Start the probe in **its own terminal** and leave it running until the end of drill 2:

```sh
curl -s -X PUT -d 'checkpoint probe' http://localhost:8081/notes/slo
while true; do curl -s -o /dev/null http://localhost:8081/notes/slo; sleep 0.5; done
```

Give it a few minutes of traffic before the rung-2 gate, or `slo-gate` will correctly refuse on "traffic over 10m: NONE". Expect two more refusals if you run the gate straight after rung 1 merges: `candidate applied on dev-01` while the stamp is still rolling the pin out (main has moved, the rung has not, and a new image tag pulls before its pod is Ready), then `candidate soaked NNs of the 2m required` once it has, stage 09 step 9's residency check, because a window that has only just met your revision was mostly measuring the one before it. All three are the gate working; wait them out and re-run.

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

Rung 1 is dev, by PR, self-merged on green:

```sh
source ./env.sh
(cd apps/overlays/dev && kustomize edit set image $APP_IMAGE:${TAG#v})
git add apps/overlays/dev
./scripts/pr-open pin/14/dev-${TAG#v} "pin(app-dev): app ${TAG#v}" <<EOF
## What is moving
Dev's app pin to ${TAG#v}.

## Why now
Act III checkpoint drill 2, rung 1: a release enters the ladder.

## Evidence
The image exists on GHCR (polled above).

## If it is wrong
Revert this merge; prod has not moved.

Refs: #14
EOF
```

Read it; when the diff is what the body claims:

```sh
gh pr checks --watch --fail-fast \
&& gh pr merge --merge --delete-branch \
&& git switch main \
&& git pull
```

Rung 2 is prod, by PR, on **both** signatures (the ladder means prod follows evidence, not hope): convergence, dev's green context, *and* performance, a clean SLO window on the dev rung, fed by the probe you started above:

```sh
gh api "repos/{owner}/{repo}/commits/$(git rev-parse HEAD)/status" \
  --jq '.statuses[] | .context + "  " + .state'   # re-run until app-dev on dev-01 reads success
./scripts/slo-gate dev-01 10m                     # the error budget survived the soak - or no promotion
```

```sh
source ./env.sh
git switch -c promote/14/app-prod \
&& (cd apps/overlays/prod && kustomize edit set image $APP_IMAGE:${TAG#v})
git add apps/overlays/prod
git commit -m "promote(app-prod): app ${TAG#v}" && git push -u origin promote/14/app-prod
gh pr create --title "promote(app-prod): app ${TAG#v}" \
  --body "Normally a comprehensive description goes here: what's moving, why now, and the evidence - dev's green context on the source commit.

Refs: #14"
gh pr diff             # one pin move - the whole promotion
```

Read it; when the diff is what the body claims:

```sh
gh pr checks --watch --fail-fast \
&& gh pr merge --merge --delete-branch \
&& git switch main \
&& git pull
```

Stop the probe once the prod rung is green (Ctrl-C in its terminal). Drills 3 to 5 measure convergence and stamp state, not SLIs.

Timings, per rung, from each rung's own commit and its cluster's context. Find each commit **by its subject**, which the [commit convention](../appendices/commit-convention.md) made a field rather than prose. `rung-time` takes the subject and resolves it through `scripts/commit-by-subject`, the lookup the drills and gates share:

```sh
./scripts/rung-time "pin(app-dev): app ${TAG#v}" \
  kustomization/app-dev/dev-01 kind-ggp-dev-01 app-dev

./scripts/rung-time "promote(app-prod): app ${TAG#v}" \
  kustomization/app-prod/prod-01 kind-ggp-prod-01 app-prod
```

> `commit-by-subject` matches the subject field exactly, first-parent, not `--grep`. A substring search would find the *revert* of a break rather than the break, since `git revert` quotes the subject it undoes, and an unanchored version match finds `0.1.10` when you asked for `0.1.1`. It is awk, so no `grep.patternType` setting can reinterpret it, and it ignores the ` (#N)` GitHub appends to a merge commit's subject.

Two details that stop this measuring the wrong thing. **Both rungs are found by their commit message, never by `HEAD`**: any commit landing after your merge (a teammate's, a bot's, a docs fix) silently becomes `HEAD` and you end up timing *its* convergence instead, which produces a plausible number for the wrong event. And **full status contexts, not prefixes**: two clusters run `app-dev`, so the declared suffix from stage 07 is what pins each timing to its own cluster.

**A measurement trap worth more than the number it protects.** Stage 04 taught that a commit can wear a **red the cluster already had**; here is its mirror, and it only shows up when you time things: a commit can wear a **green that is not a success**. A commit status has two states, and Flux's provider derives them from an event's *severity*: an error posts a failure and every other event posts a success, with the event's reason as the description. Most of those events are not "reconciliation succeeded". When a fetch lands, a stamp with `dependsOn` reconciles the new revision before its dependencies have, records "dependency not ready" and retries later; that is an info event, so it posts as **success**, on the right commit, seconds after the merge, before anything is applied. A rollout interrupted by the next commit does the same: "health checks canceled" is info too. Observed: a prod promotion merged at 21:20:27 wore `success  dependency not ready` at 21:20:31, its ReplicaSet was created at 21:20:42, and `success  reconciliation succeeded` arrived at 21:21:02. Measured by state alone that promotion took **4 seconds**; it actually took **35**. The guard above is the fix: wait for `lastAppliedRevision` to name your revision, then read the status whose description is `reconciliation succeeded`, which is what `rung-time` does. And the general rule is the same one this whole act keeps teaching: **ask the cluster what it applied; ask git what you asked for; never let a green stand in for either.**

**Record: dev rung and prod rung lead times.**

### 3. Fleet detection - the dashboard finds it

Drill 2 measured how fast a **good** change reaches a cluster. This one measures how fast a **bad** one reaches a human, the number that justifies everything stage 09 built. (Reminder: a *stamp* is a Flux `Kustomization` CR; `app-prod` is the stamp binding the app to the prod cluster.)

Two signals are about to disagree, on purpose. A **commit status** is a snapshot that whichever reconcile happened to finish chose to post: drill 2 met one that was green about a revision the cluster had not applied. A **metric** is a continuous sample of the stamp's own Ready condition, taken every scrape, whether or not anything interesting is happening. Detection is a metric question; attribution is a status question. Watch the metric win.

**Step 1: open the dashboard, before you break anything.** You cannot see a change you never saw the "before" of. The port-forward blocks, so give it its own terminal and leave it up for the whole drill:

```sh
kubectl --context kind-ggp-local-01 -n monitoring port-forward svc/kube-prometheus-stack-grafana 3000:80
```

| | |
|---|---|
| **URL** | <http://localhost:3000> |
| **Username** | `admin` |
| **Password** | `prom-operator` |
| **Dashboard** | *Flux Cluster Stats*, via the sidebar search |
| **What to look at** | the not-Ready / failing panels, and the `cluster` label on each row |

Three clusters, every stamp green. That is the picture you are about to spoil.

**Step 2: break prod.** Quietly, as if you weren't the one doing it:

```sh
source ./env.sh
(cd apps/overlays/prod && kustomize edit set image $APP_IMAGE:9.9.9)
git add apps/overlays/prod
./scripts/pr-open break/14/prod "break(app-prod): absent image" <<'EOF'
## What is moving
Prod's app pin to 9.9.9, which does not exist.

## Why now
Act III checkpoint drill 3: a health failure on one rung, found from the dashboard.

## Evidence
None - that is the test.

## If it is wrong
The next PR reverts this merge.

Refs: #14
EOF
```

Read it; when the diff is what the body claims:

```sh
gh pr checks --watch --fail-fast \
&& gh pr merge --merge --delete-branch \
&& git switch main \
&& git pull
```

**Step 3: watch, don't measure.** Stay on the dashboard. Roughly what to expect:

| When | On the dashboard |
|---|---|
| first ~60s | nothing at all: Flux hasn't fetched yet. The fleet is *correctly* still green about a repo it hasn't read |
| ~1–2 min | one row leaves Ready: `app-prod` on `cluster=prod-01`. Dev and platform stay green, so the blast radius is visible without you knowing where to look |
| after that | that row **blinks**: Unknown for the 3m health check, not-Ready for the 30s `retryInterval`, Unknown again as the next attempt starts. Most of the time it reads Unknown, and it never reads Ready |

**One thing that looks like a second failure and isn't: for a few seconds, *several* rows go red at once, across all three clusters.** Every stamp with a `dependsOn` marks itself Ready=**False**, reason `DependencyNotReady`, while the dependency it names is still reconciling the new revision. Flux chose False for that, not Unknown, so it is indistinguishable from a real failure in any panel that only reads the Ready value. Measured: nine stamps red at 13:22:10 (`app-*`, `monitoring`, `monitoring-crs` on hub, dev and prod), eight of them green again by 13:22:40, `app-prod` the only one still red. The stamps with no dependencies never flicker: `flux-system`, `cluster-secrets`, `infrastructure`. The tell is duration, not colour: **the cascade clears in one retry (30s); the real failure doesn't.** It fires on *every* push, including a docs commit that changes no manifest at all, which is why an alert on `ready="False"` with no `for:` will page you for a typo fix in a README. The cascade posts a **commit status** too, and that one is stranger: state `success`, description `dependency not ready`, a green whose own text says otherwise.

Meanwhile prod is still serving. Ask it at any point during the break:

```sh
curl -s -o /dev/null -w '%{http_code}\n' http://localhost:8082/healthz   # → 200, throughout
```

Health gating means the bad image never took traffic: Flux applied the new spec, the rollout could not complete, and the ReplicaSet that was already serving kept serving. The stamp failed, the workload didn't. That distinction is the whole point of drill 4.

**Step 4: now put a number on it.** The dashboard told you *what*; this asks the same data *when*, and prints the state timeline either side of the break so the answer shows its working. Note what it does **not** need: the commit. The break's subject is `break(app-prod): …` by convention, so naming the stamp already selects the commit, the grammar paying for itself in the smallest possible way. That is the drill's convenience, not the tool's assumption: a real break is never labelled, it is a feat or a pin or a promote that happened to hurt, and it is found the other way round, from the revision the stamp's `status.history` names as failed (drill 4 reads it); pass that sha as the third argument and the timeline reads the same.

```sh
./scripts/detect-time app-prod kind-ggp-prod-01
```

```
break commit   9470bb4  "break(app-prod): absent image"
               pushed at 13:21:25 - app-prod was ready=True

what the hub saw (gotk_resource_info, 15s resolution):

  13:19:25            ready=True
  13:22:10     +45s   ready=False      transient (30s) - the dependency cascade, not your break
  13:22:40     +75s   ready=Unknown    <- left Ready: the dashboard can see something is wrong
  13:25:40    +255s   ready=False      <- confirmed red: the stamp gave up
  13:30:40    +555s   ready=True       recovered

break -> left Ready:      75s
break -> confirmed red:  255s   (180s of that spent waiting out timeout 3m0s)
```

Three things that timeline is teaching, none of them the number:

- **It reads the metric, not the status, because they answer different questions.** A status is *event-driven*: notification-controller publishes one when a reconcile ends, and it can beat the metric (observed: `failure` at +233s, three scrapes before the metric's `+255s`). But its **state is not a verdict on your commit**. Today's break wore a `success` at +31s whose own description read *"dependency not ready"*: the cascade, published as green. And drill 2 met a `success` posted about the *previous* revision. The metric has no such problem: it is a continuous sample of the condition itself, labelled by `name` and `cluster`, queryable after the fact and across the fleet. Statuses tell you *which commit, which cluster, whose*; metrics tell you *what state, since when*.

- **The break is found by its exact subject, never by `HEAD`.** `git revert` puts the reverted commit's subject inside its own, so a substring search finds the revert, newer, and the opposite event.
- **Red is not a state, it's a rhythm.** The stamp retries every `retryInterval` (30s since stage 08), and each retry reads Unknown for the whole health timeout until it gives up again, so a failing stamp is Unknown far more than it is red. And it isn't only broken stamps that flash, since every push reds the whole dependent fleet for a scrape (above). Anything alerting on not-Ready needs a `for:` longer than both gaps, or it pages on healthy commits. *Why* it failed is a different question and a different tool, and step 5 asks it.

**Step 5: triage, then restore.** The dashboard named the rung. Attribution walks down from there one layer at a time, and each layer names the next. First hop, the stamp:

```sh
flux get kustomizations --context kind-ggp-prod-01
flux events --context kind-ggp-prod-01 --for Kustomization/app-prod | tail -3
```

```
Warning  HealthCheckFailed  Kustomization/app-prod  health check failed after 3m0.0s: timeout waiting for: [Deployment/ggp/app status: 'InProgress']
Warning  HealthCheckFailed  Kustomization/app-prod  health check failed after 16.6ms: failed early due to stalled resources: [Deployment/ggp/app status: 'Failed']
```

Read what the stamp knows and what it does not. Its reason is `HealthCheckFailed` and its message names the *object* that failed health, `Deployment/ggp/app`. The same failure wears two messages: `timeout waiting` while the Deployment is still trying, then `stalled` once the Deployment's own progress deadline has passed and Flux stops waiting for it (by the time you look, `tail -3` may show only the later form, with the earlier one further up the list). Notice too what `flux get` shows for `app-prod`'s revision: still the promotion, while every other stamp names the break. The break was applied, failed health, and never became the stamp's applied revision, which is drill 4's question answered early. What the stamp cannot say is *why*, because Flux applied the Deployment and the Deployment is all it watches; why a pod will not start is the Deployment's business. So the second hop is the object the message named, and the objects below it:

```sh
kubectl --context kind-ggp-prod-01 -n ggp get deploy app \
  -o jsonpath='{range .status.conditions[*]}{.type}={.status} {.reason}{"\n"}{end}'
kubectl --context kind-ggp-prod-01 -n ggp get pods
kubectl --context kind-ggp-prod-01 -n ggp get events --field-selector reason=Failed \
  -o custom-columns='COUNT:.count,POD:.involvedObject.name,MESSAGE:.message' \
  | sed 's/: rpc error.*: /: /'    # the runtime's wrapping dropped; the last words are the cause
```

```
Available=True MinimumReplicasAvailable
Progressing=False ProgressDeadlineExceeded
NAME                       READY   STATUS             RESTARTS   AGE
app-577c6ff5cd-h85js       1/1     Running            0          57m
app-577c6ff5cd-qb9ss       1/1     Running            0          57m
app-74d569d8c4-rk8bv       0/1     ImagePullBackOff   0          15m
azurite-6b89b98654-zdmqt   1/1     Running            0          3h22m
COUNT   POD                    MESSAGE
5       app-74d569d8c4-rk8bv   Failed to pull image "ghcr.io/…/gitops-golden-path-app:9.9.9": not found
5       app-74d569d8c4-rk8bv   Error: ErrImagePull
64      app-74d569d8c4-rk8bv   Error: ImagePullBackOff
```

Three facts, one per object. The Deployment is still `Available`, because the old ReplicaSet serves, and has stopped `Progressing`, because the new one never will. The new pod is in `ImagePullBackOff`. The pull failed because the tag does not exist. That is the cause, two objects below the row the dashboard showed you, and every hop was named by the layer above it: stamp, reason and object, Deployment condition, pod, event. The `fleet-triage` skill walks this ladder. Now revert:

```sh
sha=$(./scripts/commit-by-subject --prefix 'break(app-prod): ')   # the break by its subject, never by HEAD
./scripts/pr-revert "$sha" "Drill 3: restore prod; the dashboard named the rung, the pod's events named the cause."
```

Read it; when the diff is what the body claims:

```sh
gh pr checks --watch --fail-fast \
&& gh pr merge --merge --delete-branch \
&& git switch main \
&& git pull
```

The sha is looked up, not assumed. Bare, `pr-revert` takes `HEAD`, and `HEAD` is the break only if nothing else landed while you worked: a teammate's merge, a bot's, a seed sync of your own, and the revert undoes the wrong thing while the break stays live. The subject is the durable handle; the grammar pays for itself again.

**Record both numbers: left Ready, and confirmed red.** Wait for the revert's green on the dashboard before drill 4.

### 4. The evidence question - across clusters

The auditor, again, harder: *"Between the break and the restore, what was prod actually running, who fixed it, and how do you know dev was unaffected?"* Durable artifacts only: memory and terminal scrollback are off-limits.

One command, because a dossier is a deliverable and not a pile of raw query output:

```sh
./scripts/evidence 'break(app-prod): '
```

```
THE CHANGE
----------
  commit         61e1ee0  break(app-prod): absent image (#130)
  author         <you> <you@example.com>
  committed      2026-09-02T13:32:58+01:00
  files          apps/overlays/prod/kustomization.yaml
  blast radius   app-prod on prod-01  (from the status context that never posted: it did on the parent commit)

WHO TOUCHED THIS PATH AFTERWARDS
--------------------------------
  7fedd48   2026-09-02T13:59:29+01:00  Revert "break(app-prod): absent image (#130)" (#131) <you>
  61e1ee0   2026-09-02T13:32:58+01:00  break(app-prod): absent image (#130)                 <you>

WHAT THE FLEET SAID, IN ORDER
-----------------------------
  2026-09-02T12:33:19Z  success   kustomization/infrastructure/prod-01  reconciliation succeeded
  2026-09-02T12:33:19Z  success   kustomization/cluster-secrets/prod-01  reconciliation succeeded
  ...
  2026-09-02T12:34:58Z  success   kustomization/monitoring-crs/local-01  reconciliation succeeded

  success: 14
  silent: 1   kustomization/app-prod/prod-01  (posted on the parent commit, never on this one)
  (the /status endpoint shows only this last line - the latest per context. The
   sequence above needs /statuses, and the sequence is what shows a green whose
   description is not 'reconciliation succeeded'.)

WHAT THAT CLUSTER ACTUALLY APPLIED
----------------------------------
  now running    7fedd48  Revert "break(app-prod): absent image (#130)" (#131)
  verdict        this commit is an ancestor of what the cluster runs now
                 (true after a revert too - the revert is also an ancestor. What the
                  cluster served DURING the failure is the status sequence above.)
  gave up        2026-09-02T12:36:48Z  (first HealthCheckFailed event; the stamp's own verdict)

THE ANSWER, IN ENGLISH
----------------------
  <you> changed app-prod on 2026-09-02.
  The fleet reconciled that commit everywhere; only prod-01 never posted
  on it, because only its render changed and its stamp never converged (on Flux
  2.8.x a failure does not post, so the silence is the red). Reconcile scope is
  the repo, change scope is the paths the commit touched.
  The failure was a health check, not an apply error - which is the whole point:
  the stamp failed and the workload did not. The cluster kept serving the last
  revision that passed, so the artifacts prove a negative (the bad version never
  ran) without anyone having been watching.
```

Note the blast-radius line and what produced it. **Nothing was told which cluster to look at**: the script read the one status context that had posted on the parent commit and not on this one, `kustomization/app-prod/prod-01`, and split the stamp and cluster straight out of it. From Flux 2.9 that context posts a `failure` instead and the same line reads "from the status context that went red"; the derivation is the same. That is the [identifier alignment rule](../appendices/repo-leak-posture.md) collecting: one string names the stamp, the namespace, the label, the metric, the commit scope *and* the status context, so a tool handed a red context already knows which file to open.

Now read what the script actually did, because the lesson is the queries and not the existence of a script. Each is a line or two against an artifact that outlives everyone who was on the call, and each answers one question. Run them one at a time:

> Known issue on the pinned 2.8.8 bundle: no failure posts a commit status ([notification-controller#1373](https://github.com/fluxcd/notification-controller/issues/1373), fixed in Flux 2.9 by [#1317](https://github.com/fluxcd/notification-controller/pull/1317)), so until the pin moves `app-prod`'s context sits **absent** on the break commit rather than red, the verdict held in the stamp's conditions and events. From 2.9 on the queries below read as written.

**Who touched the path, and when.** Git, first-parent, so the merges and not the branch commits beneath them:

```sh
sha=$(./scripts/commit-by-subject "break(app-prod): absent image")   # exact subject, so the revert cannot win
git log --first-parent --format='%h  %cI  %s  (%an)' "$sha^..HEAD" -- apps/overlays/prod
# → 7fedd48  2026-09-02T13:59:29+01:00  Revert "break(app-prod): absent image (#130)" (#131)  (<you>)
# → 61e1ee0  2026-09-02T13:32:58+01:00  break(app-prod): absent image (#130)  (<you>)
```

**Which clusters reported, and what.** The forge, one line per context, the latest post per context:

```sh
gh api "repos/{owner}/{repo}/commits/$sha/status" \
  --jq '.statuses[] | .context + "  " + .state'
# → kustomization/infrastructure/prod-01  success
# → kustomization/cluster-secrets/prod-01  success
# → (the rest, all success; no kustomization/app-prod/prod-01 line at all)
```

Every context `success`, and `kustomization/app-prod/prod-01` is missing. On the 2.8.8 pin the absence *is* the red: the stamp never converged, so it never posted, and this pin posts no failure event at all. From 2.9 on the line is there and reads `failure`. The reading is the same either way: every cluster reconciled this commit, and only prod's app stamp has anything against it.

**The sequence.** The same statuses with every post and its time, oldest first:

```sh
gh api "repos/{owner}/{repo}/commits/$sha/statuses" \
  --jq '.[] | .created_at + "  " + .context + "  " + .state + "  " + .description' | tac
```

What the summary above collapses, this keeps: the order the clusters fetched, seconds apart, and, from 2.9 on, where prod's failure fell among the greens. It is also where a green that is not a success shows up (drill 2).

**What prod ran, before, during and after.** The cluster: the stamp's `status.history`, one entry per render, keyed by the digest of what was applied:

```sh
kubectl --context kind-ggp-prod-01 -n flux-system get kustomization app-prod -o json \
  | jq -r '.status.history[] | .firstReconciled + "  " + .lastReconciled + "  x" + (.totalReconciliations|tostring)
           + "  " + .lastReconciledStatus + "  " + .metadata.revision[0:17]'
# → 2026-09-02T11:52:13Z  2026-09-02T13:10:54Z  x12  ReconciliationSucceeded  main@sha1:7fedd48
# → 2026-09-02T12:36:48Z  2026-09-02T12:59:52Z  x35  HealthCheckFailed  main@sha1:61e1ee0
# → 2026-09-02T09:27:35Z  2026-09-02T11:46:52Z  x29  ReconciliationSucceeded  main@sha1:5399723
```

Read the second answer once more: **all three clusters reconciled this commit; only prod changed.** A shared source means every cluster fetches every commit, so "reconciled" is not evidence of "affected": the paths the commit touched decide that, and this one touched only `apps/overlays/prod/`. Had it touched `base/`, the same one-line diff would have reached all three with no promotion at all: the ladder gates what lives on a rung, and nothing else. That asymmetry is the argument for path-scoped review (CODEOWNERS on `base/`, `clusters/`, prod overlays, `infrastructure/`, the gates themselves). See [stage 07 §4](../act-2/stage-07.md#4-promotion-is-a-pr-that-moves-a-pin), where the paths and their reasons are listed.

The last answer is the sharpest in the course so far. Read the history: the break's render was reconciled every 30s for the length of the break (`x35` here) and failed every time, so `lastAppliedRevision` never named it. The render prod runs now carries the digest it had before the break, first reconciled at the promotion; the promotion, the revert and everything since share that one line, because the revert restored the same bytes, and the line's revision names the latest commit to produce that render, not the first. Health gating means the broken change never became prod's truth, and the artifact proves a negative ("the bad version never ran") without anyone having watched.

**Now as a document.** A dossier that lives in scrollback is not a deliverable either. The `audit-evidence` skill, seeded at stage 00 into `.claude/skills/`, runs the same queries and writes them up in one fixed shape: the question verbatim, the controls exercised (control → mechanism → evidence → where it was retrieved), a timeline with one source per line, findings, and the gaps it could not close. In Claude Code, from the config repo:

```
/audit-evidence between the break and the restore, what was prod running, who fixed it, and how do we know dev was unaffected?
```

Read the result as an auditor would: every line must point at an artifact, and anything the artifacts could not answer belongs under "Gaps", not silently missing. Keep it, because an audit answer is itself a change record. The skill does the keeping: it writes `docs/audits/<date>-<slug>.md`, stages it and opens the PR with `pr-open` on a `docs/14/…` branch citing this work item, then stops, which leaves you on that branch with a clean tree and a PR to read. Merging is yours; no skill merges anything. If you wrote the dossier by hand from the queries above, put it at that path and do the same by hand:

```sh
git add docs/audits
./scripts/pr-open docs/14/audit-app-prod-break "docs(audits): app-prod break and restore, from artifacts" <<'EOF'
## What is moving
docs/audits/<date>-<slug>.md: the auditor's question, answered from git, the statuses and the stamp's history.

## Why now
Act III checkpoint drill 4: an audit answer is a change record, so it lands like one.

## Evidence
Every line of the dossier cites the artifact it came from; what the artifacts could not answer is under Gaps.

## If it is wrong
Revert this merge; the artifacts it cites are unchanged.

Refs: #14
EOF
```

Either way, read it (`gh pr diff`, and every claim in the body should name its artifact); when the diff is what the body claims:

```sh
gh pr checks --watch --fail-fast \
&& gh pr merge --merge --delete-branch \
&& git switch main \
&& git pull
```

Merge it before the tag.

### 5. The four numbers - from the drills you just ran

Stage 10 computed the four numbers over history the fleet had recorded on its own. This time the history is yours, and short: drill 1 rebuilt the hub, so the store was born with the fleet; drill 2 put one change into production; drill 3 broke it and reverted it. You know what the numbers should say before you ask, which is the only condition under which a metric can be checked rather than believed.

```sh
./scripts/dora --window 6h
```

```
window       last 6h   (2026-09-02 -> 2026-09-02)
production   prod-.*   (1 unit: platform/prod-01)
source       gotk_resource_info + kube_deployment_metadata_generation, 60s resolution
RETENTION    data begins 2026-09-02 10:14, not 2026-09-02 08:31 - the hub keeps less history than the window
             asked for. Every rate below is over the SHORTER span; a long --window
             on a short retention reports a quiet fleet rather than a missing one.

DORA (production)
  deployment frequency          22.86/day           (2 distinct changes)
  lead time for changes  median 71s     p95 84s     commit -> production, first arrival
  change failure rate           50%                 (1 incident / 2 changes)
  time to restore        median 9m      p95 9m      per incident, last unit recovered

  denominator  2 changes over 2.1 hours across 1 production unit.
               Too few to steer by - DORA is a trend instrument, not a spot reading.

reconciles   14 stamp revision changes across all rungs produced 3 production
             application(s), which are 2 distinct change(s). Reconcile is not
             change, and an application is not a deployment.
refused      1 of those application(s) the stamp never reported as applied - a rollout
             refused on health. An application, not a change; its commit is not a lead time.
```

Your numbers will differ; the shape will not, and every line of it is checkable against what you did:

- **`RETENTION` is expected, and it is drill 1's doing.** The hub's store is pod-local, so the rebuild took the history with it and the data begins when the monitoring stamp came back. Stage 10 warned that retention silently narrows the window; here you know exactly why the span is short, and the script still refuses to report the quiet hours before the store existed as a quiet fleet.
- **Two changes, not one and not three.** Drill 2's release is one. The revert is the second: it moved prod's pin and the workload's generation moved with it. The break is not a third: Flux applied it and then refused it on health, so the generation moved but the stamp never reported a new applied revision. The script books each application against the first revision the stamp reports after it, and one with no new revision before the next application is the `refused` line: an application, not a change. That is the `3 production application(s), which are 2 distinct change(s)` pair: the unit is what production says it is running.
- **The lead time is the prod rung by another route.** The headline starts at the commit the production stamp applied, the promotion, so it should agree with `rung-time`'s prod number to within a source interval. It says nothing about rung 1 or the soak, which is what `--stages` is for, below.
- **One incident over two changes is 50%**, and the denominator line says why not to steer by it. A window you built to contain one break will always read like this: the metric is a trend instrument.
- **Time to restore is the number drill 3 did not record.** From the stamp leaving Ready to the revert's green: the `recovered` row `detect-time` printed. Most of it is your own reading time between drill 3's steps 3 and 5, which is honest, because on a real fleet that interval is the on-call.

Now the interval the headline hides. Drill 2 left exactly the two commits `--stages` joins, `pin(app-dev): app V` and `promote(app-prod): app V`, so the release can be traced back past its promotion:

```sh
./scripts/dora --window 6h --stages
```

```
WHERE THE LEAD TIME GOES
The headline above starts at the commit the production stamp applied - which is
the PROMOTION, not the change. Everything before it is invisible there, and is
usually most of the elapsed time. DORA exists to expose exactly that.

  change                         dev->PR      review merge->prod       TOTAL
  -------------------------  ----------- ----------- ----------- -----------
  0.1.1-run20260902123512            14m         18s         84s         16m
  7fedd48                              -         25s         71s          2m
  median                             14m         18s         71s          2m
```

The release is the row with all three intervals, named by its version token: `dev->PR` is the soak you gave rung 1 before opening the prod PR, `review` is the seconds between `gh pr create` and your merge, and `merge->prod` is the headline. The revert has no `pin(app-dev)` behind it, so it is named by its sha and its `dev->PR` is a dash: it never climbed. The join that found the release's dev commit is the version token drill 2's two subjects carried; nothing else in the system links them, which is the [commit convention](../appendices/commit-convention.md) paying out one more time.

Last, the split that stage 22 will make interesting:

```sh
./scripts/dora --window 6h --by tenant
```

```
DIAGNOSTIC - within production, by tenant. Not four more DORA readings: the metric
is the fleet number above, and this says which tenant is moving it.

  tenant          applied    lag (med)    lag (p95)
  platform              3          71s          84s

  applied = per-unit applications, NOT deployments. One change reaching every
  unit is one deployment; these rows sum to more and must never be added up.
```

One row, and it can only mirror the fleet: `applied` is three because the break was applied before it was refused, and the lags are the headline's two, the refused application contributing none. Before stage 22 there is one tenant, the platform; the row exists so that when there are fifty it says which one is dragging the fleet.

**Record: lead time (the headline), time to restore, and change failure rate with its denominator.**

## AI enhancement

**How.** One skill, `run-drill`, running drill 1 again as one script and stopping where the human's line is: the tag and the closing of the item. The other drills are not repeated: the skills they use have their second outings inside the stages (`promote` at stages 07 and 09, `fleet-triage` at 04 and 09) and in Act VI's audit drill (`audit-evidence`). Run it from the config repo in Claude Code, on `main` with a clean tree. The rebuild erases what the clusters hold (events, `status.history`, and this time the hub's store), which is why drill 5 ran by hand before it.

**Drill 1, the rebuild.** `run-drill` runs `scripts/act-3-drill`, drill 1 as one script: three clusters down and up, `cluster-sync` each, the root keys paid, the fleet converged with the monitoring stack included, checkpoints 07 to 09, and the number from artifacts. It runs the script detached and reads its log, since the drill outlives a tool call, and writes the pack on `#14`: the number with its source, the findings. Be on `main` with a clean tree; the script refuses otherwise. Bare, it prints what it would destroy and refuses:

```
/run-drill rebuild act-3
```

Then, having read the blast radius, the run. Longer than Act II's nine minutes: the monitoring stack is the heavy pull.

```
/run-drill rebuild act-3 --yes
```

Expect the skill to poll `/tmp/act-3-drill.log` (`tail -n 5` on it if you want to watch too), report `fleet-from-nothing: NNNs` from the results line, and comment the pack on `#14`. Expect one thing gone: the hub's store went with the hub, so `dora` now knows nothing before the rebuild. That is stage 10's retention warning in the flesh, and why drill 5 ran before this.

**Why.** A drill's value is the evidence pack, and the pack is where hand-run drills go thin: the number gets typed from memory. The script gives the verdicts and the number; the skill sequences the run and writes the pack.

**Where.** After the checkpoint has been run by hand once, and before its work item is closed: the skills' PRs cite `#14`, and `issue-gate` wants it open at merge.

**Verify.** What the rebuild leaves. The pack: the number on the work item agrees with the table below, and the store is empty behind it:

```sh
gh issue view 14 --comments | grep -in 'fleet-from-nothing'
./scripts/dora --window 6h     # → RETENTION dated the rebuild, then "no production change in the window"
```

And no skill merged anything:

```sh
git log --first-parent --merges --format='%h  %s' stage-10..
# → every line a merge you ran
```

## Pass criteria

- [ ] All five drills completed; numbers recorded below.
- [ ] Zero `kubectl apply`/`edit`/`scale` in drills 2–5; prod touched only by PR.
- [ ] The prod rung merged on **both signatures**: dev's green context *and* a passing `slo-gate`, convergence and performance.
- [ ] The evidence question answered from durable artifacts alone, per cluster.
- [ ] The dossier landed under `docs/audits/` by a PR citing `#14`.
- [ ] The four numbers read from `dora` over the checkpoint's own window, denominator quoted, with drill 3's break visible in change failure rate and time to restore.
- [ ] The config repo tagged `act-3`, the boundary `act-3-drill` rebuilds to, the checkpoint's work item closed and the milestone with it ([using the course §5](../using-the-course.md#5-tags-at-every-boundary)):

```sh
git tag act-3 && git push --tags
gh issue close 14 --comment "act-3 tagged" && gh api -X PATCH "repos/{owner}/{repo}/milestones/3" -f state=closed
```

The tag makes the act one range. Read it once: it is the act's change as git holds it, and nothing in it arrived any other way:

```sh
git diff act-2..act-3 --stat
# → the hub and its agents with their stamps and alerts on every cluster, the SLO rule and
#   its tests, stage 08's workload baseline and check, this act's scripts, the pins the
#   drills moved, docs/audits: about 80 files
```

| Measure | Value | Date |
|---|---|---|
| Fleet-from-nothing | – | – |
| Dev rung (merge → green on dev-01) | – | – |
| Prod rung (merge → green on prod-01) | – | – |
| Break → left Ready (dashboard) | – | – |
| Break → confirmed red (stamp gave up) | – | – |
| Lead time (DORA headline: promotion → first production arrival) | – | – |
| Time to restore (DORA: break merged → recovered) | – | – |
| Change failure rate (DORA: incidents / changes) | – | – |

Reference values from a three-cluster kind fleet: fleet-from-nothing ≈400s against Act II's ≈535s, the difference being `retryInterval`; dev rung ≈80s and prod rung ≈35s with the image already pulled, and minutes more when a fresh tag pulls slowly, because the rung is not green until the pod is Ready and the pull is inside the number; break → left Ready ≈75s and confirmed red ≈255s, of which 180s is the health timeout. The three DORA rows are the same events by another route: the lead time is the prod rung plus wherever in the source's minute the merge fell, and time to restore is the break's merge to the revert's green. Yours come from artifacts, not from this sentence.

## After the checkpoint

- Found a broken step? Fixes to the walkthrough are PRs against the course repo.
- **From here the course operates what it built.** Act IV operates the ladder (gates, rendered review, the platform and the robots on the rungs, the version ladder climbing), Act V does secrets properly on a live fleet, Act VI adds the second axis. Each assumes exactly the fleet you have now, which is why they come after this checkpoint and not before it.

---

**Next:** [11 - Shift left (git hooks, and the style gate)](../act-4/stage-11.md)
