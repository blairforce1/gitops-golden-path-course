# Stage 04 - Closing the loop

[← 03 - Flux bootstrap](stage-03.md) · [Walkthrough index](../README.md)

> **Where you are:** the config repo root, on `main`. **Starting state:** stage 03's end state: Flux reconciling `app-dev` from the remote, everything green.

**Goal:** the outcome lands on the commit itself - a green tick or a red X - the human informed without asking: the loop invariant's last step ([rule 5.1](../rules.md#51-the-loop-invariant-merge--reconcile--observable-outcome--human-informed)). Then test the loop five ways: one happy path, one break per failure layer - and learn which failures reach the commit, which stay silent by design, and which registers hold the detail behind each verdict.

## Steps

### 1. The token IOU (deliberately wrong, loudly)

The GitHub commit-status provider needs a token. Secrets management arrives in stage 06; today we cheat, *and record the debt*:

```sh
kubectl -n flux-system create secret generic github-status-token \
  --from-literal=token=$(gh auth token)
```

An imperative secret: unrecorded, unrotated, invisible to git. **IOU: stage 06 pays back the debt**, the first use of the IOU pattern ([rule 5.3](../rules.md#53-the-iou-pattern-do-it-the-wrong-way-loudly)). (Fine-grained PAT with commit-status permission is the better token when you make this real.)

### 2. Provider + Alert

Two files, per the naming convention: the CLI writes them, then read what it wrote (the Provider is *where* to tell, the Alert is *what* to tell it about):

```sh
source ./env.sh
flux create alert-provider github-status \
  --type=github --address="https://github.com/$GH_OWNER/$CONFIG_REPO" \
  --secret-ref=github-status-token \
  --export > clusters/platform/local-01/resources/github-status.provider.yaml

flux create alert app-dev-status \
  --provider-ref=github-status \
  --event-source="Kustomization/app-dev" --event-severity=info \
  --export > clusters/platform/local-01/resources/app-dev-status.alert.yaml

git add clusters/platform/local-01/resources
./scripts/pr-open feat/5/notify-app-dev "feat(local-01): commit status from app-dev reconciliations" <<'EOF'
## What is moving
A github Provider and an Alert on Kustomization/app-dev, in local-01's binding.

## Why now
The loop has no last step yet: nothing tells a human whether a merge landed.

## Evidence
Two CLI-written files; the token they reference is the stage-04 IOU, imperative for now.

## If it is wrong
Revert this merge - statuses stop, nothing else changes.

Refs: #5
EOF
```

Read it; when the diff is what the body claims:

```sh
gh pr merge --merge --delete-branch \
&& git switch main \
&& git pull
# the cluster folder applies these, so flux-system is the stamp to converge
flux reconcile kustomization flux-system --with-source
```

That was the seven lines of stages 02–03 with the first four scripted. `pr-open` branches, commits, pushes and opens from whatever is **staged**, lints the subject and body first, refusing a body that cites no open work item, which is `issue-gate`'s one job ([rule 2.5](../rules.md#25-every-change-has-a-work-item-the-trailer-is-the-reason)), prints the diff, and stops. The merge is never automated, in this course or after it: merging is a decision, and the diff is what informs it ([rule 2.4](../rules.md#24-every-change-is-a-pr-the-branch-is-scaffolding-the-pr-is-the-artifact)). This stage merges twelve PRs, which is the point: by the end of it the shape is in your hands, not on the page. Its sibling `pr-revert` does the same for rollbacks: `git revert -m 1` on a branch, git's own subject, a body built from the reverted merge plus the one sentence you supply. Same boundary: it opens the PR and stops - the merge is never delegated, not even for a rollback.

So, what did that merge just buy? Flux is now configured to post a **commit status** back to GitHub for every commit the stamp reconciles (a *stamp* is stage 03's coinage for a Flux `Kustomization` CR). In the portal that is the green tick on the commit: in the commit list it sits beside the author line as `✓ 1/1`, a count of passing statuses, and clicking it names each one by context. (The `Verified` badge over by the sha is a different fact - that is your commit signature, not the loop.) From the CLI it is the query the next step runs. A commit can carry many statuses, one per context, and the context here is `kustomization/app-dev/<id>`: the stamp's name plus an opaque hex suffix - the Provider object's truncated UID, accidental identity that stage 07 replaces with a declared per-cluster name, so several clusters can post to the same repo without colliding *and* be named from the string alone. That is the shape the fleet will grow into - one commit, a status per stamp; exactly what a glance can and cannot tell you is what the next step measures. We will put it to the test in the next step.

### 3. Testing the alert (five ways)

One happy path, then one break per failure layer. Everything lands via git: a commit that changes or breaks, observe, a commit that reverts. You never trigger a reconcile: being told, unaided, is the entire point of this stage. Expect each status ≲70s after push (the source interval), except where noted. **Pace yourself: wait for each revert's green before pushing the next case.** Two pushes inside one source interval make Flux fetch straight to the newer commit. The middle one never becomes an artifact and never gets any status: statuses attach to revisions Flux reconciled, not to every commit you made. When a case goes wrong, triage with the ladder, in order: `flux get kustomizations` → `flux events` → `flux logs --follow --kind=Kustomization --name=app-dev` → `flux tree kustomization app-dev`.

> **Known issue on the pinned 2.8.8 bundle:** testing this walkthrough on Flux 2.8.8 hit an upstream regression - the v1.8 notification pair drops every failure event before the commit-status provider sees it, so the red Xs below never post; only greens do ([notification-controller#1373](https://github.com/fluxcd/notification-controller/issues/1373), fixed by [#1317](https://github.com/fluxcd/notification-controller/pull/1317), shipped in Flux 2.9). If `flux check` reports 2.8.x, read each break's verdict from `flux get kustomizations` and `flux events` instead; from 2.9 on the statuses behave as written.

**1. Happy path.** A deployment-*level* annotation, not pod-template level, so nothing restarts; the change is pure metadata, which makes the arriving status unambiguously the loop's doing:

```sh
cat >> apps/overlays/dev/patches/app.deployment.patch.yaml <<'EOF'
- op: add
  path: /metadata/annotations
  value:
    platform.example.com/loop-test: stage-04
EOF

git add apps/overlays/dev/patches
./scripts/pr-open test/5/loop-test "test(app-dev): the loop posts green on a good change" <<'EOF'
## What is moving
A harmless annotation on dev's Deployment.

## Why now
First exercise of the notification loop: a change that must go green.

## Evidence
One annotation; the render diff is one line.

## If it is wrong
The next PR reverts it regardless.

Refs: #5
EOF
```

Read it; when the diff is what the body claims:

```sh
gh pr merge --merge --delete-branch \
&& git switch main \
&& git pull
```

Open the merge commit on GitHub (a tick next to the sha), or ask from the CLI; re-run until it flips from absent/pending. Note *which* commit wears it: the merge commit, because `main` only ever advances by merges and Flux only ever sees `main`. The branch commit gets no status, ever:

```sh
gh api "repos/{owner}/{repo}"/commits/$(git rev-parse HEAD)/status \
  --jq '.state + "  " + (.statuses[0].context // "no status yet")'
# → success  kustomization/app-dev/<id>
```

Revert: a second PR, a second green status for free, and the overlay back to canonical:

```sh
./scripts/pr-revert "The loop test passed; the annotation has done its job."
```

Read it; when the diff is what the body claims:

```sh
gh pr merge --merge --delete-branch \
&& git switch main \
&& git pull
```

**2. Fetch, and the alert stays silent.** Break the fetch layer on a scratch source:

```sh
flux create source git broken-source \
  --url=https://github.com/example/does-not-exist --branch=main --interval=1m \
  --export > clusters/platform/local-01/resources/broken-source.gitrepository.yaml

flux create kustomization fetch-test \
  --source=GitRepository/broken-source --path=./ --prune --interval=5m \
  --export > clusters/platform/local-01/resources/fetch-test.kustomization.yaml

git add clusters/platform/local-01/resources
./scripts/pr-open break/5/fetch "break(flux-system): fetch layer, a source that cannot exist" <<'EOF'
## What is moving
A scratch GitRepository pointing nowhere, and a stamp on it.

## Why now
Failure layer 1 of 4: does a fetch failure reach the commit?

## Evidence
None - the break is the experiment.

## If it is wrong
It is wrong on purpose; the next PR reverts it.

Refs: #5
EOF
```

Read it; when the diff is what the body claims:

```sh
gh pr merge --merge --delete-branch \
&& git switch main \
&& git pull
```

```sh
flux get sources git      # broken-source Ready=False - the fetch error names the URL
flux get kustomizations   # fetch-test failing; app-dev untouched
gh api "repos/{owner}/{repo}"/commits/$(git rev-parse HEAD)/status \
  --jq '.state + "  " + (.statuses[0].context // "no status yet")'
# → success  kustomization/app-dev/<id>   ← GREEN (re-run until a status appears). Read that again.
```

The break is real (`flux get sources git` says so) and the commit shows **green**: app-dev reconciled this commit fine, and the objects actually failing are not in the Alert's `eventSources`, which is an **allowlist, not a net**. Two lessons in one: the status belongs to a *stamp*, not to your commit's intent, and every alert has a scope - anything outside it fails in silence. (Stage 09's fleet dashboards watch everything precisely so that scoped alerts are allowed to stay scoped.) Revert, and note the cleanup is prune doing deletion-by-git, as stage 03 taught:

```sh
./scripts/pr-revert "Fetch-layer experiment done: the alert stayed silent, as its allowlist dictates."
```

Read it; when the diff is what the body claims:

```sh
gh pr merge --merge --delete-branch \
&& git switch main \
&& git pull
```

**3. Build.** Reference a file that doesn't exist:

```sh
# rule 3.5 twice over: the owning tool writes the file (yq would re-indent every list
# in it), and it refuses to reference a missing file unless told - the break is deliberate
(cd apps/overlays/dev && kustomize edit add resource missing.yaml --no-verify)
git add apps/overlays/dev
./scripts/pr-open break/5/build "break(app-dev): build layer, a missing resource" <<'EOF'
## What is moving
Dev's kustomization references a file that does not exist.

## Why now
Failure layer 2 of 4: a render that cannot build.

## Evidence
None - the break is the experiment.

## If it is wrong
It is wrong on purpose; the next PR reverts it.

Refs: #5
EOF
```

Read it; when the diff is what the body claims:

```sh
gh pr merge --merge --delete-branch \
&& git switch main \
&& git pull
```

Gate: wait for the red before you act. A build failure is fast - it exists the moment the new revision is fetched - so it lands on the source interval like the green did. Read both channels side by side:

```sh
gh api "repos/{owner}/{repo}"/commits/$(git rev-parse HEAD)/status \
  --jq '.state + "  " + (.statuses[0].context // "no status yet")'
# → failure  kustomization/app-dev/<id>
flux events --for Kustomization/app-dev | tail -3   # the build error names missing.yaml
```

The commit wears the X and the cluster holds the sentence behind it: `flux get kustomizations` carries the full error, Ready goes False, and `missing.yaml` is named outright. Contrast with fetch: that failure was outside the Alert's *scope* and stayed silent; this one is inside it and reached you unaided. The status says *that* it broke; the cluster's registers say *why* - the ladder connects the two, and the next two breaks walk it further down the pipeline.

Red seen, error read. Then recover:

```sh
./scripts/pr-revert "Build-layer experiment done: red seen, error read."
```

Read it; when the diff is what the body claims:

```sh
gh pr merge --merge --delete-branch \
&& git switch main \
&& git pull
```

**4. Apply.** Change something the API server will refuse. The Deployment's selector is immutable (this is why stage 02 set `includeSelectors: false`):

```sh
cat >> apps/overlays/dev/patches/app.deployment.patch.yaml <<'EOF'
- op: replace
  path: /spec/selector/matchLabels
  value:
    app.kubernetes.io/name: renamed
EOF

git add apps/overlays/dev/patches
./scripts/pr-open break/5/apply "break(app-dev): apply layer, an immutable selector" <<'EOF'
## What is moving
Dev's Deployment selector - a field the API server will refuse to change.

## Why now
Failure layer 3 of 4: a render that builds and is rejected on apply.

## Evidence
None - the break is the experiment.

## If it is wrong
It is wrong on purpose; the next PR reverts it.

Refs: #5
EOF
```

Read it; when the diff is what the body claims:

```sh
gh pr merge --merge --delete-branch \
&& git switch main \
&& git pull
```

Gate: the same shape as the build layer, one step later in the pipeline - the render built, and the API server refused it. The X arrives on the source interval; the rejection reads back verbatim:

```sh
gh api "repos/{owner}/{repo}"/commits/$(git rev-parse HEAD)/status \
  --jq '.state + "  " + (.statuses[0].context // "no status yet")'
# → failure  kustomization/app-dev/<id>
flux events --for Kustomization/app-dev | tail -3   # server rejection: field is immutable
```

Red seen, rejection read. Then recover:

```sh
./scripts/pr-revert "Apply-layer experiment done: red seen, rejection read."
```

Read it; when the diff is what the body claims:

```sh
gh pr merge --merge --delete-branch \
&& git switch main \
&& git pull
```

**5. Health, the slow one.** A plausible-but-absent image tag. Fetch OK, build OK, apply OK, everything green-looking; then `wait: true` holds until the rollout times out (3m on the stamp). Health is the only failure that happens *after* a successful apply: the cluster accepted the change, and the change then failed to become true:

```sh
source ./env.sh
(cd apps/overlays/dev && kustomize edit set image $APP_IMAGE:9.9.9)
git add apps/overlays/dev
./scripts/pr-open break/5/health "break(app-dev): health layer, an image that does not exist" <<'EOF'
## What is moving
Dev's app pin to 9.9.9, a tag that does not exist.

## Why now
Failure layer 4 of 4: everything passes until the rollout times out.

## Evidence
None - the break is the experiment.

## If it is wrong
It is wrong on purpose; the next PR reverts it.

Refs: #5
EOF
```

Read it; when the diff is what the body claims:

```sh
gh pr merge --merge --delete-branch \
&& git switch main \
&& git pull
```

Gate: slow by design - the health verdict only exists after the 3m rollout timeout (~1m + 3m from merge). Watch the symptom while you wait, then read the status channel:

```sh
# ImagePullBackOff - the symptom lives in the app namespace
kubectl -n ggp get pods
gh api "repos/{owner}/{repo}"/commits/$(git rev-parse HEAD)/status \
  --jq '.state + "  " + (.statuses[0].context // "no status yet")'
# → failure  kustomization/app-dev/<id> - the slowest X, and the only one that postdates a clean apply
```

Four layers, four tempos: fetch never reached the commit (scope), build and apply went red on the source interval, health went red only after the rollout timed out. The X is the loop's failure half working - nothing polled, and the bad news still found the commit. What the X cannot tell you is *why*: that lives in the conditions and events, which is why the ladder, not the status, is the diagnostic tool.

Red read. Then recover:

```sh
./scripts/pr-revert "Health-layer experiment done: the slowest red, as designed."
```

Read it; when the diff is what the body claims:

```sh
gh pr merge --merge --delete-branch \
&& git switch main \
&& git pull
```

After every break: the revert converges and posts its green. The break commit keeps its red forever - **the incident pair is readable from history alone** - and the diagnosis detail stays durable in the cluster's registers.

### 4. Reading the conditions

For one of the failures, look at the raw truth the CLI summarises:

```sh
kubectl -n flux-system get kustomization app-dev -o jsonpath='{.status.conditions}' | jq
```

Ready/Reconciling/Stalled, with reasons and timestamps: this is what dashboards (stage 09) and the commit statuses are built from.

## Stop & measure

- [ ] `scripts/checkpoint-04` reports all PASS, exit 0 (notification objects live, IOU secret present, and the *reconciled revision* wears a green status; it queries `lastAppliedRevision`, not HEAD, for exactly the supersession reason above):

```sh
./scripts/checkpoint-04
```

- [ ] Happy path: a green status arrived without any polling by you; time from merge to status-visible measured (record it).
- [ ] Build, apply, health: a red status on the commit, `Ready=False` and the layer's own error each time, a diagnosis reached via the ladder (write one line each: layer, symptom, which rung told you). (On the 2.8.8 pin no red posts - the known issue above; the cluster-side reads still pass.)
- [ ] Fetch: **no red status**, and you can say why in one line (the failing objects aren't in the Alert's `eventSources`; the green that did appear belongs to `app-dev`, not to your commit's intent).
- [ ] Green restored after each revert: on the revert commit itself when you paced it, or on whatever commit Flux saw next if you didn't (a skipped commit never gets a status; see troubleshooting).

**End state:** everything green: the test PRs and their reverts in history (twelve merge commits: `git log --first-parent --oneline -12` reads as the stage's own log), notifications live, `app-dev` reconciling cleanly. The act checkpoint starts from exactly here.

**Measured outcomes:** merge→feedback time for both verdicts (the green, and each break's red - health's the slowest by design); four failure layers each diagnosed in under ~5 minutes using only the ladder.

Tag the boundary ([using the course §5](../using-the-course.md#5-tags-at-every-boundary)):

```sh
git tag stage-04 \
&& git push origin stage-04 \
&& gh issue close 5 --comment "stage-04 tagged"
```

## Audit artifacts produced

- **The deployment record is attached to the change itself**, with its character understood: every commit Flux *reconciled* carries the stamp's verdict at that revision, green or red, reviewable years later, queryable via the GitHub API. It is **telemetry, not a per-commit verdict**: superseded commits carry no status, and a commit can wear a red it didn't cause (the stamp was already broken when it landed). The lossless record behind it is the Kustomization's status transitions and event stream; per-commit judgement of the *diff* arrives with CI at PR time (stage 07+). Still CC8 change-management evidence accruing as a side effect: just cite it as "what was running when", not "whether this commit was good".
- **Failure evidence persists**: the broken commits wear their reds beside their reverts' greens, a complete incident micro-narrative in history, with each failure's detail durable in the Kustomization's status transitions and event stream; nothing had to be written up.
- The four break/revert pairs are your first **change-failure-rate and MTTR data points** (DORA #3 and #4, joining stage 03's lead time). Data points, not yet metrics: [stage 10](../act-3/stage-10.md) computes all four over a window, per cluster and per tenant, once stage 09's hub is there to read them from.
- Debt register: one imperative secret (the IOU). Notably, *even the debt is visible*: `kubectl -n flux-system get secret github-status-token` has no counterpart in git, which is exactly how stage 06 will find it.

## AI enhancement

**How.** The `fleet-triage` skill (seeded at stage 00 into `.claude/skills/`) walks the four-layer ladder from an identifier: it splits `kustomization/<stamp>/<cluster>` into the binding file and the kube context, reads the conditions and events layer by layer, stops at the first failure, and reads the applied revision beside the status sequence before it believes a green. Ask it with the identifier from the status or the alert, or with "why hasn't my change appeared".

**Why.** The commands are the ones this stage taught. The judgment is in the order, in stopping at the first failing layer, and in not mistaking a stale green or a dependency cascade for a failure. That is sequencing over the same evidence, which is what a skill is for; the verdicts stay with the scripts.

**Where.** After step 3, on each of the four breaks: break by PR, then ask the skill before you look, and compare its layer and reason string with what you found by hand.

**Verify.** The reason string it quotes matches `flux events` verbatim; the file it names is the one you edited; its fix is a PR (a revert), never a `kubectl` command. If it proposes anything else, that is a defect in the skill, and the finding goes in the course's issues.

## Troubleshooting

| Symptom | Likely cause | Fix |
|---|---|---|
| No status appears on the commit | Alert/Provider not reconciled, or token lacks status permission | `flux get alerts`; `flux events --for Provider/github-status`; token needs commit-status (classic `repo:status`) |
| No break ever shows a red status | You are on the Flux 2.8.x notification pair (the current AKS bundle): a known upstream issue drops failure events before the commit-status provider sees them (`missing commit metadata key` in its log; [notification-controller#1373](https://github.com/fluxcd/notification-controller/issues/1373), fixed in Flux 2.9 by [#1317](https://github.com/fluxcd/notification-controller/pull/1317)) | Read the verdict from `flux get kustomizations` and `flux events` until the pin moves; the reds post as written from 2.9 on |
| Status on the wrong commit | Flux reports the *applied revision* | It marks the commit the Kustomization applied; push again if you amended |
| Immutable-selector break doesn't fail | `includeSelectors` crept to true, selector already matched | Check rendered selector with `kustomize build`; the patch must target the selector itself |
| Health break goes green | `wait: true` missing on the Kustomization | It was set in stage 03; confirm it survived your edits |
| `v1beta3` unknown kind | Older Flux | `flux version`; use the API version your CLI scaffolds (`flux create alert --export` shows it) |
| Events show nothing for a failure | Looking in the app namespace | Flux CR events live in `flux-system`; `flux events` scopes correctly by default |
| kubectl/flux: `connection refused` to `127.0.0.1:<port>` | The kind container died (host/podman restart, OOM) | `docker ps -a --filter name=ggp-local-01` to confirm; `docker start ggp-local-01-control-plane`; state and port mapping survive a restart. Then `./scripts/checkpoint-03` to prove the platform recovered; Flux catches up on missed commits by itself |
| `flux reconcile` hangs; changes land only on interval ticks, never ≲70s | kustomize-controller wedged; two controller pods means the new one is waiting on a dead pod's leader lease | The escalation ladder below the table |
| A commit stays "pending  no status yet" forever | Superseded within the source interval: the next push landed before the fetch, so this commit never became an artifact | Expected, not a failure: statuses attach to reconciled revisions. The *content* still landed (it's in the newer commit's tree); the next reconciled commit carries the verdict. Pace pushes ≳1 source interval apart when you want per-commit evidence |

> When the machinery itself is stuck, escalate in order, cheapest first. (1) Nudge: `flux reconcile <stamp> --with-source`. (2) Recycle the controller: `kubectl -n flux-system rollout restart deploy/kustomize-controller`, and delete the old pod if it lingers - while it holds the leader lease, the new pod sits idle. (3) Recycle the node: `docker restart ggp-local-01-control-plane`, then `./scripts/checkpoint-03` to prove recovery. (4) Rebuild from git: `cluster-up` plus stage 03's cluster-side block. One move that is *not* on the ladder: deleting a stuck Kustomization CR - with `prune: true`, deleting the object deletes everything it owns (the namespace included), which on a real fleet is an outage, not a repair. The ladder ends at a rebuild on purpose: [rule 5.2](../rules.md#52-the-cluster-is-derivable-from-git---and-every-act-proves-it) means you are never more than a few minutes from a clean platform, and that - not pod surgery - is the real answer to a wedged cluster.

## What you learned, and what's next

The loop is complete: merge → reconcile → observable outcome → you were told, on the commit itself. You've broken the system at all four layers: fetch, build, apply, health. You've triaged each with the same ladder, so failure is now a diagnosable place, not a mystery. And you've met the sharpest edge of alerting: the fetch break never made a sound (an alert's `eventSources` is an allowlist and anything outside it fails silently; scope is a design decision, not a default). The commit status revealed its true nature too: **convergence telemetry projected onto git, not a per-commit verdict** - it samples at the source interval, skips superseded commits, and reports the world's health rather than the diff's quality. CI (stage 07+) judges the diff; Flux reports the world; stage 09's dashboards watch what git cannot say. All three channels, never confused. Along the way you collected your first DORA data points, and one deliberate debt (the imperative token secret) sits waiting for stage 06.

**Next:** the act checkpoint - the whole loop exercised end to end, timed, including rebuilding the platform from nothing. Then Act II grows this single-cluster loop into production shape: Helm for third-party software, secrets done properly, the promotion ladder, health gates, and observability at fleet scale.

---

**Next:** [Act I checkpoint](act-checkpoint.md)
