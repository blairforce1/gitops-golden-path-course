# Act I checkpoint - the complete loop, end to end

[← 04 - Closing the loop](stage-04.md) · [Walkthrough index](../README.md)

> **Where you are:** the config repo root, on `main`, tree clean and pulled; kubectl context `kind-ggp-local-01`. **Starting state:** stage 04's end state - `checkpoint-03` and `checkpoint-04` passing, `stage-04` tagged. **Before you start:** `source ./env.sh`; the app repo cloned beside this one with a clean tree (drill 2 tags it); `gh auth status` green; a stretch where destroying the platform cluster is acceptable - drill 1 begins by deleting it.

Run this only when stages 00–04 are individually green. It exercises the whole act as one system and produces the numbers that seed the repo's measurable-outcomes claims. The checkpoint is where you level up: the drill proves the loop is yours, not the walkthrough's.

## The drill

**No stopwatch anywhere:** every timing below is extracted afterwards from artifacts the system already stamped: commit dates, status `created_at`, condition transition times. The metrics are queries, like the evidence. (One consequence: the clock starts at the merge commit's own timestamp, so read the diff *before* you merge; reading after merging is billed as lead time.)

**Automated re-runs:** once you've done the drills by hand, `scripts/act-1-drill --yes` re-earns all four numbers unattended. It's destructive (rebuilds the cluster, pushes a dated pre-release tag, opens and merges three real PRs), which is why it demands the flag. Use it as a regression harness after walkthrough or config changes; the numbers below should stay in the same ballpark.

### 1. Cold start - platform from nothing, timed

Everything inline (no flicking back to stages 03/04):

```sh
source ./env.sh
./scripts/cluster-down && ./scripts/cluster-up

./scripts/cluster-sync clusters/platform/local-01
```

Nothing is committed: the components and the sync pair merged at stage 03 and the new cluster takes them from git; the deploy key is minted afresh and replaces the dead cluster's - `cluster-sync` deletes the old key by title before registering the new one, so nothing stale lingers. Expect stage 03's "new public key was added" email from GitHub again: every rebuild sends one, and recognising it as your own rebuild is the point of that aside. Now watch the IOU register itself, then pay it:

```sh
# FAILs twice: the token secret is the visible debt, and without it the fresh cluster's
# first green could not post - one debt, two symptoms; that's the design
./scripts/checkpoint-04
kubectl -n flux-system create secret generic github-status-token \
  --from-literal=token=$(gh auth token)
```

**Era note (from stage 06 on):** once secrets are SOPS-managed, the debt consolidates to one root key. Pay *that* instead, and git restores the token itself:

```sh
kubectl -n flux-system create secret generic sops-age \
  --from-file=age.agekey=$HOME/.config/gitops-golden-path/age/local-01.agekey
```

> `act-1-drill` and `checkpoint-04` detect the era themselves: the drill pays whichever IOU the repo's state calls for, and the checkpoint reports whether the token is imperative or git-restored.

Wait for the platform, then pull the time out of the artifacts: cluster birth is the `kube-system` namespace's creation stamp; done is `app-dev`'s first successful reconcile, read from the stamp's `status.history`. Not from the Ready condition's `lastTransitionTime`: with `wait: true` that flips on every reconcile, so it reads the latest interval tick rather than the first convergence, and the number grows by up to 5m depending on when you look. A history entry's `firstReconciled` is written once:

```sh
echo -n "waiting for the platform (checkpoint-03 passes; usually 1-3m) "
until ./scripts/checkpoint-03 >/dev/null 2>&1; do printf .; sleep 10; done; echo
./scripts/checkpoint-03 && ./scripts/checkpoint-04

t0=$(kubectl get ns kube-system -o jsonpath='{.metadata.creationTimestamp}')
t1=$(kubectl -n flux-system get kustomization app-dev -o json \
  | jq -r '[.status.history[]? | select(.lastReconciledStatus == "ReconciliationSucceeded") | .firstReconciled] | min')
echo "platform-from-nothing: $(( $(date -d "$t1" +%s) - $(date -d "$t0" +%s) ))s"
```

If `checkpoint-04`'s status line is still bare, the first reconcile finished before the token existed and its event was dropped; the next success event posts the green - within a stamp interval, or now with `flux reconcile kustomization app-dev`.

**Record: platform-from-nothing time.** This is the recovery story (struggle point 9) and the DR posture (rebuild, not failover) in miniature. It is also the first proof of [rule 5.2](../rules.md#52-the-cluster-is-derivable-from-git---and-every-act-proves-it): every act ends by rebuilding from nothing, and each act's checkpoint redefines "nothing".

### 2. A real change, no kubectl - lead time

Prerequisite once: a real `:0.1.1` image. The app repo's publish workflow triggers on `v*` tags, so a tag *is* a release. No code change needed; the point is a new immutable version to move a pin to:

```sh
source ./env.sh
cd "$APP_DIR"
git pull
git tag v0.1.1 && git push origin v0.1.1

# the image, not the workflow, is the prerequisite - poll the registry
# until it exists (~2-3m, multi-arch build):
echo -n "waiting for the registry to have 0.1.1 "
until docker manifest inspect $APP_IMAGE:0.1.1 >/dev/null 2>&1; do printf .; sleep 10; done
echo " published"
cd -                                # back to the config repo
```

Then, by PR, the shape you have used since stage 02:

```sh
source ./env.sh
(cd apps/overlays/dev && kustomize edit set image $APP_IMAGE:0.1.1)
git add apps/overlays/dev
./scripts/pr-open pin/6/app-0-1-1 "pin(app-dev): app 0.1.1" <<'EOF'
## What is moving
Dev's app pin, 0.1.0 to 0.1.1.

## Why now
Checkpoint drill 2: a real release, a real change, no kubectl - timed from merge to green.

## Evidence
The image exists on GHCR (polled above).

## If it is wrong
Drill 3 breaks and restores this rung deliberately.

Refs: #6
EOF
```

Read it; when the diff is what the body claims:

```sh
gh pr merge --merge --delete-branch \
&& git switch main \
&& git pull
```

Wait for the green tick unaided (~70s), then extract the timing: commit stamp to the status's server-side `created_at`, no clock involved. This helper serves the whole checkpoint; paste it once per shell:

```sh
lead() { local sha; sha=$(git rev-parse "${1:-HEAD}")
  local t0 t1
  t0=$(git log -1 --format=%cI "$sha")
  t1=$(gh api "repos/{owner}/{repo}/commits/$sha/status" --jq '.statuses[0].created_at')
  echo "${sha:0:7}  merge->status $(( $(date -d "$t1" +%s) - $(date -d "$t0" +%s) ))s  ($(git log -1 --format=%s "$sha") -> $(gh api "repos/{owner}/{repo}/commits/$sha/status" --jq .state))"; }

lead HEAD    # → merge->green (lead time)
```

**Record: lead time.**

### 3. A real failure - detection and restore

```sh
source ./env.sh
(cd apps/overlays/dev && kustomize edit set image $APP_IMAGE:9.9.9)
git add apps/overlays/dev
./scripts/pr-open break/6/absent-image "break(app-dev): absent image" <<'EOF'
## What is moving
Dev's app pin to 9.9.9, which does not exist.

## Why now
Checkpoint drill 3: a health failure must go red and be restored, unaided - break to red, revert to green, both timed from artifacts.

## Evidence
None - that is the test.

## If it is wrong
The next PR reverts this merge.

Refs: #6
EOF
```

Read it; when the diff is what the body claims:

```sh
gh pr merge --merge --delete-branch \
&& git switch main \
&& git pull
```

Wait for the red status unaided (slow by design: ~1m + the 3m rollout timeout; on the 2.8.8 pin no red posts - [stage 04's known issue](stage-04.md#troubleshooting) - so detect via `Ready=False` instead). Then read the error behind it:

```sh
flux get kustomizations    # app-dev Ready=False - the sentence behind the X
```

Then revert; the pacing lesson applies, let the revert's green land before moving on:

```sh
./scripts/pr-revert "Drill 3: restore after the deliberate break."
```

Read it; when the diff is what the body claims:

```sh
gh pr merge --merge --delete-branch \
&& git switch main \
&& git pull
```

Two timings, both from the status register - the break's red and the revert's green, each against its own merge stamp:

```sh
lead HEAD~1   # the break → break->red (detection)
lead HEAD     # the revert → revert->green (restore)
```

**Record: time-to-detect (break→red) and time-to-green.**

### 4. The evidence question - from artifacts only

Role-play, six months later. An auditor asks about the change in (2): *"Prove what changed, who made it, when, whether the deployment succeeded, and what the cluster runs now."* Answer using durable artifacts only; memory and terminal scrollback are off-limits (git history is fine: git *is* the artifact). Start cold: find the change by query and pin its sha in a variable, then three queries against it, under two minutes:

```sh
# by grammar, not eyeball - first-parent so it is the merge, not the branch commit;
# anchored both ends, allowing the ' (#N)' the merge subject gains from the PR number
sha=$(git log --first-parent --format=%h --extended-regexp --grep='^pin\(app-dev\): app 0\.1\.1( \(#[0-9]+\))?$' -1)

git log -1 --format='change:   %h  %s%nauthor:   %an <%ae>%nwhen:     %cI' "$sha"
# a merge commit carries no diff of its own - read it against the first parent, the PR's whole change
git diff-tree --no-commit-id --stat "$sha^" "$sha" | sed 's/^ */          /'
gh api "repos/{owner}/{repo}/commits/$sha/status" \
  --jq '"outcome:  \(.state)  (\(.statuses[0].context), \(.statuses[0].created_at))"'
rev=$(kubectl -n flux-system get kustomization app-dev -o jsonpath='{.status.lastAppliedRevision}')
echo "running:  $rev"
git merge-base --is-ancestor "$sha" "${rev##*:}" \
  && echo "included: yes - the change is an ancestor of the applied revision"
```

The expected output is the auditor's answer, one labeled line per question:

```
change:   06f9fbe  pin(app-dev): app 0.1.1 (#76)
author:   <owner> <your-git-email>
when:     2026-08-31T18:19:01+01:00
          apps/overlays/dev/kustomization.yaml | 5 ++++-
          1 file changed, 4 insertions(+), 1 deletion(-)
outcome:  success  (kustomization/app-dev/<id>, 2026-08-31T17:19:38Z)
running:  main@sha1:<head-sha>
included: yes - the change is an ancestor of the applied revision
```

The last two lines matter together: the cluster reports the *latest* applied revision, not your change's sha, because later commits have landed since. "Is my change deployed?" is therefore an ancestry query, and `merge-base --is-ancestor` answers it from git alone.

Note what *didn't* happen: nobody wrote anything up, yet the story reconstructed cold. Drills 1–3 tested behaviours; this one tests a **property**: complete change-management evidence accrued as a by-product of the loop and is retrievable by query. That property is the seed of `docs/compliance-map.md`: authorization (the commit/PR), outcome (the status), deployment record (the applied revision), all queried, none remembered.

## AI enhancement

**How.** `run-drill` runs this checkpoint as a game day: it states what "nothing" means here (every kind cluster; git and the root keys survive), runs `act-1-drill` with the flag, watches with the what-to-expect table, measures with `rung-time` and `detect-time`, and writes the pack on the checkpoint's work item with one `audit-evidence` dossier per injected change. `fleet-triage` answers drill 3's "what broke" from the red's context and the stamp's conditions and events. Call `run-drill` with the drill (`rebuild act-1`) and the explicit `--yes`; `fleet-triage` with the red's context identifier.

**Why.** A drill's value is the evidence pack, and the pack is where hand-run drills go thin: the numbers get typed from memory and the refusals are not collected. The skill sequences the drill and writes the pack; the drill script and the checkpoint keep the verdicts.

**Where.** After the four drills have been done by hand once. The first run is yours.

**Verify.** Every number in the pack has a source line; the pack's dossiers match `evidence` run by hand; nothing in the pack came from a clock.

## Pass criteria

- [ ] All four drills completed; the four numbers recorded in the table below.
- [ ] Zero `kubectl apply`/`edit`/`scale` used anywhere in drills 2–4.
- [ ] The evidence question answered from durable artifacts alone.
- [ ] The config repo tagged `act-1`, the checkpoint's work item closed and the milestone with it ([using the course §5](../using-the-course.md#5-tags-at-every-boundary)):

```sh
git tag act-1 && git push origin act-1
gh issue close 6 --comment "act-1 tagged" && gh api -X PATCH "repos/{owner}/{repo}/milestones/1" -f state=closed
```

| Measure | Value | Date |
|---|---|---|
| Platform-from-nothing | 77s | 2026-08-12 |
| Merge → green (lead time) | 45s | 2026-08-12 |
| Break → red (detection) | 230s | 2026-08-12 |
| Revert → green (restore) | 184s | 2026-08-12 |

Current values from an `act-1-drill` run on normal bandwidth. Two earlier hand-run data points worth keeping: the first cold start measured **692s tethered to a phone**, same platform, ~9× slower, so the rebuild's cost is almost entirely image-pull latency (exactly what a registry cache/mirror attacks). And restore once measured **25s** against 184s here: both are honest. A push that lands just before a source fetch skips most of the interval wait, one that lands just after eats all of it, so per-commit timings vary by up to a source interval plus rollout. Trends across runs mean more than any single number.

## After the checkpoint

- Found a broken step? Fixes to the walkthrough are PRs against the course repo, the same seven lines you have been typing all act.

---

**Next:** [05 - Helm via Flux](../act-2/stage-05.md)
