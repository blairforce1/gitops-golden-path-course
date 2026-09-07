# Act IV checkpoint - the ladder is operated, not rehearsed

[← 16 - The version ladder climbs](stage-16.md) · [Walkthrough index](../README.md)

> **Where you are:** the config repo root, on `main`, tree clean and pulled. **Starting state:** stage 16's end state: the fleet green with the robot writing at dev and the Receiver on the platform cluster, the version ladder equal to AKS's window or one minor up, `stage-16` tagged. **Before you start:** `source ./env.sh`; the three root age keys under `~/.config/gitops-golden-path/age/` (the rebuild pays exactly those, plus one flag); `gh auth status` green; the repository setting from stage 14 step 4 still on (`can_approve_pull_request_reviews` lives on the forge, so the rebuild never touches it, and without it the robot's PR cannot open); a stretch where destroying all three clusters is acceptable - the first drill deletes the fleet.

Run this only when stages 11 to 16 are individually green. It exercises the act as one system: fleet rebuild with the robot's privilege paid; a release entering the ladder by robot on an event and climbing it by human on a digest, with the rendered blast radius on the PR that decides; the three gates refusing on the laptop what CI would otherwise have caught; and the evidence question asked of a record that robots and humans wrote together. The platform's own ladder (stage 13) and the version ladder (stage 16) are read back in the pass criteria, from the pins and the history each left. Terminology reminder for the drills: a *stamp* is a Flux `Kustomization` CR. Same rule as every checkpoint: **no stopwatch anywhere**: timings come from artifacts (commit stamps, the `ImageRepository`'s scan time, per-context status `created_at`, `status.history`).

## The drills

### 1. Fleet from nothing - with a robot in it

Act III rebuilt the fleet from git plus three root keys. The claim to test now: the fleet rebuilds from git, the same three keys, and one flag. Every kind cluster is destroyed. What survives is git, the class root keys, and the robot's *privilege*: not its key, which `cluster-sync --write` mints anew and registers in the destroyed one's place, but the decision that the platform cluster's key may push. That flag is the act's fourth IOU and the first one that is not a human's. Everything else the act built is in git and comes back unasked: stage 14's two extra controllers from the merged components file, its image objects and stage 15's Receiver from the platform binding, the Receiver's token through `cluster-secrets`, the digest pins and the policy that holds every rung to them.

This drill is one script, `scripts/act-4-drill`, and the `run-drill` skill runs it. Acts I to III typed the rebuild so that "nothing" was learned by hand; a team runs it as a file, once, and the pack it writes is the evidence. Read the script before you run it: its header is the blast radius, and its body is the three clusters down and up, `cluster-sync` each with `--write` on the platform cluster alone, the three root keys paid, the convergence wait on `checkpoint-07`, the sweep, the number from artifacts and the forge's witness. Be on `main` with a clean tree and `gh auth status` green; the script refuses otherwise. Bare, the skill prints what the script would destroy and stops:

```
/run-drill rebuild act-4
```

Then, having read the blast radius, the run:

```
/run-drill rebuild act-4 --yes
```

Expect the skill to run the script detached and poll `/tmp/act-4-drill.log` (`tail -n 5` on it if you want to watch too), report `fleet-from-nothing: NNNs` from the results line, and comment the pack on `#21`. It stops there: the tag and the item's close are yours, at the end of the page. In the log, every cluster's first table shows `cluster-secrets` red on `secrets "sops-age" not found` and its dependants waiting on it: the key cannot exist before Flux is installed, so the first reconcile fails on purpose, and the wait after the keys is the retry. Among the platform sync's lines, the three that carry the act:

```
== deploy key 'flux local-01' (READ-WRITE)
   replaced the previous 'flux local-01' key (#<id>) - a rebuilt cluster is a new identity
   registered: flux local-01  read_only: false
```

The two spokes print `read-only` and `read_only: true` on the same lines: the widening is one cluster's, and the flag on one line is the whole of it. **The hub address survives the rebuild**, as at Act III: `cluster-facts` names it by the platform node's container name, which the rebuilt node keeps, so the spokes' remote-write reconnects with zero commits. (If yours pins an IP because your environment does not resolve container names: `./scripts/refresh-hub-address`, read the three-line diff, PR and merge it before the wait below.)

**Check it**, while the script's objects are fresh. The sweep is the checkpoints the act's stages gate on: stage 16 held each rebuilt rung to `checkpoint-06` on the platform cluster and `checkpoint-07` across the fleet, and so does this.

```sh
CTX=kind-ggp-local-01 ./scripts/checkpoint-06 \
&& ./scripts/checkpoint-07
```

```
checkpoint-06: 9 passed, 0 failed
checkpoint-07: 12 passed, 0 failed
```

Then the act's own objects, none of which you asked for. The Receiver reconciles on its own interval once `cluster-secrets` has landed its token; the first line turns that wait into a second:

```sh
flux reconcile receiver app-artifact-published --context kind-ggp-local-01
flux get images all --context kind-ggp-local-01
kubectl --context kind-ggp-local-01 -n flux-system get receiver app-artifact-published \
  -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}  {.status.webhookPath}{"\n"}'
```

```
NAME                 LAST SCAN  SUSPENDED  READY  MESSAGE
imagerepository/app  <time>     False      True   successful scan: found <n> tags with checksum <checksum>

NAME             IMAGE                                   TAG    READY  MESSAGE
imagepolicy/app  ghcr.io/<owner>/gitops-golden-path-app  <tag>  True   Latest image tag for … resolved to <tag> with digest sha256:<digest> (previously …)

NAME                           LAST RUN  SUSPENDED  READY  MESSAGE
imageupdateautomation/app-dev  <time>    False      True   repository up-to-date

True  /hook/<64 hex characters>
```

Read three things. The policy's latest ref is the dev overlay's pin, tag and digest, so the robot agrees with git about the present and `repository up-to-date` is its first act; a registry ahead of the pin would instead open one PR to the newest tag, which is stage 14's shape and not a fault. The automation is Ready at all only because the sync above ran with `--write`; without the flag it sits on `push: permission denied` and the fix is that one sync again with the flag. And the Receiver's path is the one stage 15 printed: the token came back from git byte for byte, so the hash of it did too, and a build holding the old URL would still reach the rebuilt cluster.

The number runs from earliest cluster birth to the last app stamp's first successful reconcile anywhere: the same three stamps Acts II and III timed, read by the script from `kube-system`'s creation time and `status.history[].firstReconciled`, so the numbers compare, and the image controllers' pull is in the wait rather than in the number. Read it off the pack, never a clock:

```sh
gh issue view 21 --comments | grep -in 'fleet-from-nothing'   # → the results line, with its source
```

As at Acts II and III, the forge posts nothing: `main` did not change, the GitHub provider skips a status identical to the one already on the commit, and the greens on `HEAD` are the destroyed fleet's testimony. The witnesses are the three deploy keys `cluster-sync` re-registered and the `status.history` you just read. This act adds a column to read:

```sh
gh api "repos/{owner}/{repo}/keys" \
  --jq '.[] | select(.title | startswith("flux ")) | "  \(.title)  #\(.id)  read_only=\(.read_only)  created \(.created_at)"'
```

```
  flux local-01  #<id>  read_only=false  created <now>
  flux dev-01  #<id>  read_only=true  created <now>
  flux prod-01  #<id>  read_only=true  created <now>
```

Three keys minted minutes ago, one of them read-write. That line is the only imperative residue the act left, and it is on the forge where an auditor can read it.

**Record: fleet-from-nothing time**, and put it beside Act III's: the same shape of rebuild with two image controllers and a Receiver riding the wait, so expect it to hold rather than fall.

### 2. A release rides the ladder - by robot at dev, by hand above it

The claim: a new image reaches dev with no human in the chain, in seconds rather than an interval, and reaches prod only by a human PR carrying the digest dev ran, with the rendered blast radius on that PR. Every principal and every number comes off an artifact.

**First, traffic.** The prod rung's gate reads dev's error budget, and an SLO over zero requests is no evidence at all. Drill 1 rebuilt the fleet, so nothing is exercising the app. Start the probe in **its own terminal** and leave it running until the prod rung is green:

```sh
curl -s -X PUT -d 'checkpoint probe' http://localhost:8081/notes/slo
while true; do curl -s -o /dev/null http://localhost:8081/notes/slo; sleep 0.5; done
```

Everything below runs in one terminal, because each step reads variables the step before it set.

**Step 1: the version pair the event carries.** A CDEvent type carries its own version and the controller's SDK knows one; both come from the controller's own code, never typed:

```sh
nc=$(kubectl --context kind-ggp-local-01 -n flux-system get deploy notification-controller -o jsonpath='{.spec.template.spec.containers[0].image}'); nc=${nc##*:}
sdk=$(gh api "repos/fluxcd/notification-controller/contents/go.mod?ref=$nc" --jq .content | base64 -d | awk '/cdevents\/sdk-go/ {print $2}')
read -r CDE_SPEC CDE_TYPE < <(gh api "repos/cdevents/spec/contents/conformance/artifact_published.json?ref=$sdk" --jq .content | base64 -d | yq -p=json '(.context.version // .context.specversion) + " " + .context.type')
echo "notification-controller $nc speaks CDEvents $CDE_SPEC: $CDE_TYPE"
```

```
notification-controller v1.8.4 speaks CDEvents 0.4.1: dev.cdevents.artifact.published.0.2.0
```

**Step 2: the door the build would use.** The Receiver's path is derived from the token and the controller serves it on the `webhook-receiver` Service. A port-forward keeps the cluster off the internet; it runs in the background of this terminal and step 5 stops it by the PID captured here:

```sh
kubectl --context kind-ggp-local-01 -n flux-system port-forward svc/webhook-receiver 9292:80 >/dev/null &
PF=$!   # capture the PID: job numbers (%1) break on re-runs and in scripts
for i in $(seq 1 20); do curl -s -o /dev/null localhost:9292 && break; sleep 0.5; done
```

**Step 3: mint a release, and compose its event.** Mint first, because the event carries the artifact's digest and the registry must have it before the Receiver is told to look:

```sh
source ./env.sh
cd "$APP_DIR" && git pull
TAG="v0.1.1-run$(date +%Y%m%d%H%M%S)"
git tag "$TAG" && git push origin "$TAG"
echo -n "waiting for the registry to have ${TAG#v} (multi-arch build, ~2-3m) "
until docker manifest inspect $APP_IMAGE:${TAG#v} >/dev/null 2>&1; do printf .; sleep 10; done; echo
cd -
```

```sh
digest=$(gh api /user/packages/container/$APP_REPO/versions --jq ".[] | select(.metadata.container.tags[] == \"${TAG#v}\") | .name")
cat > /tmp/cdevent.json <<EOF
{
  "context": {
    "version": "$CDE_SPEC",
    "id": "$(uuidgen)",
    "source": "/github/$GH_OWNER/$APP_REPO/actions",
    "type": "$CDE_TYPE",
    "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  },
  "subject": {
    "id": "pkg:oci/$APP_REPO@$digest?repository_url=$APP_IMAGE",
    "source": "/github/$GH_OWNER/$APP_REPO/actions",
    "type": "artifact",
    "content": {}
  }
}
EOF
yq -p=json -oy '.subject.id' /tmp/cdevent.json
```

```
pkg:oci/gitops-golden-path-app@sha256:<digest>?repository_url=ghcr.io/<owner>/gitops-golden-path-app
```

The digest is the registry's own record for the tag: a package version's name is the digest of its manifest, and for a multi-arch build that is the index the policy resolves and the kubelet pulls by. Nothing downstream trusts the event's copy of it. The Receiver only triggers a scan, the policy records the digest it resolves from the registry itself, and the two are compared where the policy's line is read.

**Open until the fleet has an address a build can reach:** whether this drill's event comes from the build or from you. Today it is you, from the laptop, exactly as stage 15 posts it, because a port-forward is not a place GitHub's runners can reach; the seconds you record below are the Receiver's, and the lead time stage 10 measures still includes the poll. Stage 33 gives the platform cluster a public address and moves this block into the app repo's publish workflow, and that run is what settles whether the build's own event beats the poll by the same margin.

**Step 4: post, and watch the wait disappear.** The fleet's own view goes in a **new** terminal:

```sh
flux get image repository app --context kind-ggp-local-01 --watch
```

The post stays here, and measures from artifacts: the scan time before, the post, and the scan time moving:

```sh
path=$(kubectl --context kind-ggp-local-01 -n flux-system get receiver app-artifact-published -o jsonpath='{.status.webhookPath}')
before=$(kubectl --context kind-ggp-local-01 -n flux-system get imagerepository app -o jsonpath='{.status.lastScanResult.scanTime}')
t0=$(date +%s)
curl -s -o /dev/null -w 'webhook: HTTP %{http_code}\n' -X POST "http://localhost:9292$path" \
  -H 'Content-Type: application/json' -H "Ce-Type: $CDE_TYPE" --data-binary @/tmp/cdevent.json
until [ "$(kubectl --context kind-ggp-local-01 -n flux-system get imagerepository app -o jsonpath='{.status.lastScanResult.scanTime}')" != "$before" ]; do sleep 1; done
echo "scan fired $(( $(date +%s) - t0 ))s after the event; the interval is $(kubectl --context kind-ggp-local-01 -n flux-system get imagerepository app -o jsonpath='{.spec.interval}')"
```

```
webhook: HTTP 200
scan fired 2s after the event; the interval is 5m0s
```

**Step 5: the robot's half, with your hands off.** The scan starts the chain stage 14 built, and nothing in it needs you: the policy resolves the tag with its digest, the automation writes both to its branch, the workflow opens the PR and arms auto-merge, `verify` runs on the branch, the PR merges itself.

```sh
flux get image policy app --context kind-ggp-local-01
until pr=$(gh pr list --author app/github-actions --state all --limit 1 --json number,state,title --jq '.[] | "#\(.number)  \(.state)  \(.title)"' | grep "${TAG#v}"); do printf .; sleep 5; done; echo; echo "$pr"
```

```
NAME  IMAGE                                       TAG    READY  MESSAGE
app   ghcr.io/<owner>/gitops-golden-path-app      <tag>  True   Latest image tag for … resolved to <tag> with digest sha256:<digest> (previously …)
#<n>  OPEN  pin(app-dev): app <tag>
```

Wait for the merge, which is the branch's `verify` run and then auto-merge, and stop the port-forward, which has done its work:

```sh
n=${pr%% *}; n=${n#\#}
echo -n "waiting for the robot's PR #$n to merge itself (verify on its branch, then auto-merge; ~1-2m) "
until [ "$(gh pr view "$n" --json state -q .state)" = MERGED ]; do printf .; sleep 10; done; echo
git pull
kill $PF
```

Read the principals, found by the commit's subject and never by `HEAD`:

```sh
sha=$(./scripts/commit-by-subject "pin(app-dev): app ${TAG#v}")
git log -1 --format='%h  %an  %s' "$sha" && git log -1 --format='%h  %an <%ae>  %s' "$sha^2"
gh pr view "$n" --json author,mergedBy --jq '"#'"$n"' opened by \(.author.login), merged by \(.mergedBy.login)"'
```

```
<sha>  github-actions[bot]  pin(app-dev): app <tag> (#<n>)
<sha>  fluxcdbot <fluxcdbot@users.noreply.github.com>  pin(app-dev): app <tag>
#<n> opened by app/github-actions, merged by app/github-actions
```

Your name appears nowhere, and the release is on dev. One thing the robot's PR does not carry: a rendered-diff comment. A PR opened with the repository's own token runs no `pull_request` job (the forge records a `pull_request` run for it that fails before any job starts), so its checks of record are the push run's three jobs on the robot's branch, stage 14 step 4's trigger, and its blast radius is the two-line diff in one marked file. The rendered diff the act promises is on the PR that decides what prod receives, in step 6. Time the rung now:

```sh
./scripts/rung-time "pin(app-dev): app ${TAG#v}" \
  kustomization/app-dev/dev-01 kind-ggp-dev-01 app-dev
```

```
waiting for kind-ggp-dev-01 to apply main@sha1:<sha> ...
<sha>  kustomization/app-dev/dev-01: <seconds>s
```

**Step 6: prod, by hand, by digest.** Both signatures, and the pin copied from dev's overlay after checking it against the pod dev is running. Give the probe a few minutes of traffic first, or `slo-gate` refuses on `traffic over 10m: NONE`; run straight after the robot's merge and it refuses on `candidate applied on dev-01` while the pin is still rolling out, then on `candidate soaked NNs of the 2m required`. All three are the gate working; wait them out and re-run. `soak-gate` holds the same ascent to the soak `soak.yaml` declares, read off git's dates, and passes before `slo-gate` does, since the commit that put the digest on dev is older than its rollout.

```sh
source ./env.sh
tag=$(yq '.images[0].newTag' apps/overlays/dev/kustomization.yaml)
digest=$(yq '.images[0].digest' apps/overlays/dev/kustomization.yaml)
running=$(kubectl --context kind-ggp-dev-01 -n ggp get pod -l app.kubernetes.io/name=app \
  -o jsonpath='{.items[0].status.containerStatuses[0].imageID}'); running=${running##*@}
[ "$running" = "$digest" ] && echo "dev runs $digest" || echo "dev is not on the overlay's digest yet: wait for the rollout"
./scripts/slo-gate dev-01 10m
./scripts/soak-gate image prod
```

```
dev runs sha256:<digest>
== slo-gate: dev-01 over 10m ==
...
slo-gate: N passed, 0 failed
== soak-gate: image -> prod, the soak per ascent from git's dates ==
PASS  image -> prod: sha256:<digest> has run on dev since <date> (<n>h <n>m of the 2m required)

soak-gate: 1 PASS
```

```sh
(cd apps/overlays/prod && kustomize edit set image $APP_IMAGE:$tag@$digest)
git add apps/overlays/prod
./scripts/pr-open promote/21/app-prod "promote(app-prod): app $tag" <<EOF
## What is moving
Prod's pin to $tag, by digest: the artifact dev-01's pod is running (${digest:0:19}…).

## Why now
Act IV checkpoint drill 2, rung 2: the release the robot put on dev, carried up by a human on dev's evidence.

## Evidence
Dev's green context on the robot's merge; slo-gate's summary line above; soak-gate PASS on the 2m soak.yaml declares; dev's pod imageID equals the overlay's digest.

## If it is wrong
Revert this merge; prod returns to the previous tag and digest.

Refs: #21
EOF
```

Read the diff (two lines, the tag and the digest), then the comment stage 12 left, which is the blast radius the reviewer approves; it is posted by the last step of the `render` job, so it exists once the checks are green:

```sh
gh pr checks --watch --fail-fast
n=$(gh pr view promote/21/app-prod --json number -q .number)
gh api "repos/{owner}/{repo}/issues/$n/comments" \
  --jq '.[] | select(.body | startswith("<!-- rendered-diff -->")) | .body' \
  | grep -E '<summary>|^[-+] +image:|^No rendered'
```

```
<details><summary><code>apps/overlays/prod</code> (2 lines)</summary>
-        image: ghcr.io/<owner>/gitops-golden-path-app:<previous tag>@sha256:<previous digest>
+        image: ghcr.io/<owner>/gitops-golden-path-app:<tag>@sha256:<digest>
```

One root, two rendered lines, the artifact out and the artifact in: what prod will receive, computed by the repo's own pinned renderer, at the place the approval happens. When it is what the body claims, merge, then time the rung it moved:

```sh
gh pr merge --merge --delete-branch \
&& git switch main \
&& git pull
./scripts/rung-time "promote(app-prod): app ${TAG#v}" \
  kustomization/app-prod/prod-01 kind-ggp-prod-01 app-prod
```

```
waiting for kind-ggp-prod-01 to apply main@sha1:<sha> ...
<sha>  kustomization/app-prod/prod-01: <seconds>s
```

Stop the probe once the prod rung is green (Ctrl-C in its terminal). Then the check that gives this drill its name: git, the robot's policy and the two clusters name one artifact:

```sh
yq '.images[0].digest' apps/overlays/dev/kustomization.yaml apps/overlays/prod/kustomization.yaml
kubectl --context kind-ggp-local-01 -n flux-system get imagepolicy app -o jsonpath='{.status.latestRef.digest}{"\n"}'
kubectl --context kind-ggp-prod-01 -n ggp get pod -l app.kubernetes.io/name=app \
  -o jsonpath='{.items[0].status.containerStatuses[0].imageID}{"\n"}'
```

```
sha256:<digest>
---
sha256:<digest>
sha256:<digest>
ghcr.io/<owner>/gitops-golden-path-app@sha256:<digest>
```

The robot wrote the digest at dev, the promotion copied it, the policy reflected it once when the tag first won, and prod's kubelet pulled by it. A tag is what a human reads; the digest is what an auditor can hold you to, and it is the same string in four registers.

**Record: event → scan (against the interval), the dev rung and the prod rung.**

### 3. The gates refuse locally - rule 5.9 performed

[Rule 5.9](../rules.md#59-gates-not-checks---and-ci-is-a-backstop-that-never-fires) says CI is a backstop that never fires. The claim: three violations of three different kinds each stop on the laptop, at the hook that owns the question and in the order the hooks run, before the forge hears of them; and the runs on `main` stay green because there is nothing left for them to catch. Stage 11's drill bypassed the hooks to prove the backstop exists. This drill never bypasses anything, which is what an ordinary day looks like.

**Step 1: a style violation meets the pre-commit hook.** A branch that never reaches the forge, and a file in the one style the convention bans:

```sh
git switch -c break/21/gates
cat > gates-demo.yaml <<'EOF'
demo: {this: "is flow style", and: [it, is, banned]}
EOF
git add gates-demo.yaml
git commit -m "break(scripts): a flow-style file meets the pre-commit hook"
```

```
== style-gate: 1 file(s) ==
PASS  layout: one resource per file, <name>.<kind>.yaml, typed folders (layout-gate)
      gates-demo.yaml
FAIL  format matches the house style  [listed above - fix in place: scripts/style-fix]
gates-demo.yaml
  1:8       error    forbidden flow mapping  (braces)
  1:37      error    forbidden flow sequence  (brackets)

FAIL  yamllint clean  [violations listed above - fix the YAML, not the config]

style-gate: 1 passed, 2 failed
```

No commit exists. The hook ran the same `style-gate` CI would have run, on the one file the commit touches, and named the fix.

**Step 2: a malformed subject meets the commit-msg hook.** Fix the file the way the gate said, then hand the hook a subject with no grammar. The message comes in on stdin here so that the string is judged by the hook alone; a `-m` would be judged first by the course's own docs gate, which reads every subject the walkthrough tells you to type:

```sh
./scripts/style-fix gates-demo.yaml && git add gates-demo.yaml
git commit -F - <<'EOF'
fixed the yaml
EOF
```

```
== style-gate: 1 file(s) ==
PASS  layout: one resource per file, <name>.<kind>.yaml, typed folders (layout-gate)
PASS  format matches the kustomize/kyaml house style (kustofmt)
PASS  yamllint clean (the rules formatting cannot express)

style-gate: 3 passed, 0 failed
FAIL  .git/COMMIT_EDITMSG
        not type(scope): description  ->  fixed the yaml
FAIL  1 of 1 commit message(s) violate the convention
```

Style passed and the subject did not: two hooks, two questions, two verdicts, and you are still holding the message, so the fix is the same breath:

```sh
git commit -m "break(scripts): a demo file, never merges"
```

```
== style-gate: 1 file(s) ==
PASS  layout: one resource per file, <name>.<kind>.yaml, typed folders (layout-gate)
PASS  format matches the kustomize/kyaml house style (kustofmt)
PASS  yamllint clean (the rules formatting cannot express)

style-gate: 3 passed, 0 failed
PASS  1 commit message(s) obey the convention
[break/21/gates <sha>] break(scripts): a demo file, never merges
 1 file changed, 6 insertions(+)
 create mode 100644 gates-demo.yaml
```

**Step 3: a policy violation meets the pre-push hook.** The first two gates read a file and a string; this one reads what prod would *receive*. Drop the digest from prod's pin, which stage 14's rule refuses on every rung. The file kustomize writes is in the house style and the subject is grammatical, so both commit hooks pass, and the violation reaches the hook that renders:

```sh
source ./env.sh
tag=$(yq '.images[0].newTag' apps/overlays/prod/kustomization.yaml)
(cd apps/overlays/prod && kustomize edit set image $APP_IMAGE:$tag)
git add apps/overlays/prod
git commit -m "break(app-prod): pin by tag only, never merges"
git push -u origin break/21/gates
```

```
== style-gate: 1 file(s) ==
PASS  layout: one resource per file, <name>.<kind>.yaml, typed folders (layout-gate)
PASS  format matches the kustomize/kyaml house style (kustofmt)
PASS  yamllint clean (the rules formatting cannot express)

style-gate: 3 passed, 0 failed
PASS  1 commit message(s) obey the convention
[break/21/gates <sha>] break(app-prod): pin by tag only, never merges
 1 file changed, 1 insertion(+), 2 deletions(-)
== style-gate: <n> file(s) ==
PASS  layout: one resource per file, <name>.<kind>.yaml, typed folders (layout-gate)
PASS  format matches the kustomize/kyaml house style (kustofmt)
      kustofmt: apps/overlays/dev/secrets/app-secrets.secret.yaml: sops-encrypted, skipped (use --include-sops to override)
      ...
PASS  yamllint clean (the rules formatting cannot express)

style-gate: 3 passed, 0 failed
== policy-gate: rendered output vs policy/ ==
PASS  dev render passes policy (what the cluster would receive, judged before it does)
FAIL  prod render passes policy  [FAIL - - main - ghcr.io/<owner>/gitops-golden-path-app:<tag>: pinned by tag only - a tag is a label, a digest is the artifact;28 tests, 27 passed, 0 warnings, 1 failure, 0 exceptions;]

policy-gate: 1 passed, 1 failed
PASS  <n> commit message(s) obey the convention
== soak-gate: origin/main..HEAD, every promotion pointer the change moves ==
OK  a revert or a break is not an ascent - no soak is owed (revert-gate and the drill judge those)

soak-gate: 0 PASS
error: failed to push some refs to '<origin>'
```

Read the shape of the pre-push run before the verdict: every gate spoke (style green on the whole tree, policy red on prod, the docs' commit strings green, the soak gate reading a break and owing nothing) and *then* the hook failed. A hook that stopped at the first red would hide the rest; one that ran the gates in a row would return only the last one's exit code, which here is green, and this push would have gone through. The refusal names the rung, the image and the rule, and nothing left the laptop.

**Step 4: nothing reached the forge, and CI had nothing to catch.** Throw the branch away, then read the two facts:

```sh
git switch main && git branch -D break/21/gates
git ls-remote --heads origin 'break/21/*'
gh run list --workflow=verify --branch main --limit 3 --json conclusion,event,displayTitle \
  --jq '.[] | "\(.conclusion)  \(.event)  \(.displayTitle)"'
```

```
Deleted branch break/21/gates (was <sha>).
success  push  promote(app-prod): app <tag> (#<n>)
success  push  <the merge before it>
success  push  <the merge before that>
```

The first query prints nothing: the branch never existed on the forge. The second is the backstop's record since the checkpoint began: every run on `main` green, because every violation that would have turned one red was refused a room earlier. That is the rule performed rather than stated: the three reds you just read are the *whole* red output of this act's ordinary work, and none of them cost a runner a minute.

**Record: the three refusals, verbatim, and the runs on `main`.**

### 4. The evidence question - robot or human, and who reviewed

The auditor, with a harder question now that robots write to this repo: *"Which of the last ten changes to production were made by a robot, and who reviewed each?"* Durable artifacts only: memory and terminal scrollback are off-limits. The answer needs no dashboard, because robot provenance is a property of the commit grammar and the PR record.

**What changed prod, and who wrote it.** Git, first-parent, scoped to the three paths that reach the prod rung: the app overlay, the platform class overlay and the cluster's binding:

```sh
git log --first-parent -10 --format='%h  %cI  %an  %s' -- apps/overlays/prod infrastructure/overlays/prod clusters/prod
```

```
<sha>  <time>  <you>  promote(app-prod): app <tag> (#<n>)
<sha>  <time>  <you>  promote(app-prod): app <previous tag> (#<n>)
<sha>  <time>  <you>  pin(infrastructure): traefik chart <version>, prod rung (#<n>)
<sha>  <time>  <you>  bind(prod-01): infrastructure to the prod class overlay (#<n>)
...
```

Two fields answer the first half of the question, and each is read without opening a file. The author of every merge is you: a robot's merge is authored by `github-actions[bot]`, a Renovate merge by `renovate[bot]`, and neither appears on these paths. And the type of every subject is one a human writes above the entry rung: `promote`, `pin(infrastructure)` on the prod rung, `bind`, `fix`, `refactor`; never `pin(app-dev)`, the only subject the image robot's template can produce. The same query on the entry rung reads the other way, which is the design, not a leak:

```sh
git log --first-parent -4 --format='%h  %cI  %an  %s' -- apps/overlays/dev
```

```
<sha>  <time>  github-actions[bot]  pin(app-dev): app <tag> (#<n>)
<sha>  <time>  github-actions[bot]  pin(app-dev): app <previous tag> (#<n>)
<sha>  <time>  github-actions[bot]  pin(app-dev): app <tag before that> (#<n>)
<sha>  <time>  <you>  pin(app-dev): app <tag> by digest (#<n>)
```

Every robot line is the entry rung and every entry-rung line since stage 14 is the robot's. Zero of the last ten prod changes were made by a robot, and the two ladders' entry points are readable from `%an` and the scope alone.

**Who reviewed each.** The forge, one line per merge, found by its sha:

```sh
for sha in $(git log --first-parent -10 --format=%h -- apps/overlays/prod infrastructure/overlays/prod clusters/prod); do
  gh pr list --state merged --search "$sha" --json number,author,mergedBy,reviews \
    --jq ".[0] | \"$sha  #\(.number)  opened \(.author.login)  merged \(.mergedBy.login)  reviews \(.reviews|length)\""
done
```

```
<sha>  #<n>  opened <you>  merged <you>  reviews 0
<sha>  #<n>  opened <you>  merged <you>  reviews 0
...
```

Ten lines, and the honest reading of them is the finding: on a one-person repo every prod change was opened and merged by the same person on a read diff, with the required checks green and no formal review. That is the truth of this fleet and not a gap to paper over; the record says so plainly, and it is what stage 21's CODEOWNERS and a second person change. For contrast, the robot's own PR from drill 2:

```sh
gh pr view "$(gh pr list --author app/github-actions --state merged --limit 1 --json number -q '.[0].number')" \
  --json number,author,mergedBy,reviews --jq '"#\(.number)  opened \(.author.login)  merged \(.mergedBy.login)  reviews \(.reviews|length)"'
```

```
#<n>  opened app/github-actions  merged app/github-actions  reviews 0
```

No human anywhere on the dev rung, by design: the robot has exactly the human's dev privilege, which since stage 02 has been *merge on green without a second reviewer*. Prod is where a human is required, and the ten lines above show one.

**What prod received.** The digest chain, from git alone: the promotion's prod pin equals the dev pin it was copied from, on the commit before it:

```sh
sha=$(./scripts/commit-by-subject --prefix 'promote(app-prod): app ')   # the newest promotion, by its subject
git show "$sha:apps/overlays/prod/kustomization.yaml" | yq '.images[0].newTag + "@" + .images[0].digest'
git show "$sha^:apps/overlays/dev/kustomization.yaml" | yq '.images[0].newTag + "@" + .images[0].digest'
```

```
<tag>@sha256:<digest>
<tag>@sha256:<digest>
```

Two identical lines: prod received the artifact dev ran, and a reviewer reading the promotion's two-line diff was approving exactly that. The policy from stage 14 step 7 is why the second line could not have been a tag alone.

**Now as a document.** The `audit-evidence` skill runs the same queries and writes them up in one fixed shape: the question verbatim, the controls exercised, a timeline with one source per line, findings, and the gaps it could not close. In Claude Code, from the config repo:

```
/audit-evidence which of the last ten prod changes were made by a robot, and who reviewed each? the ten newest first-parent commits touching apps/overlays/prod, infrastructure/overlays/prod or clusters/prod
```

Read the result as an auditor would: every line must point at an artifact, and anything the artifacts could not answer belongs under "Gaps", not silently missing. Expect the two findings above stated plainly (zero robot merges on the prod paths, read from the author and the scope; every merge self-approved on green checks) and the digest chain as a third. The skill writes `docs/audits/<date>-<slug>.md`, stages it and opens the PR with `pr-open` on a `docs/21/…` branch citing this work item, then stops on that branch with a clean tree and a PR to read. Merging is yours. If you wrote the dossier by hand from the queries above, put it at that path and do the same by hand:

```sh
git add docs/audits
./scripts/pr-open docs/21/audit-robot-provenance "docs(audits): robot provenance on prod, from the commit grammar and the PR record" <<'EOF'
## What is moving
docs/audits/<date>-<slug>.md: which of the last ten prod changes a robot made and who reviewed each, from git and the PR record.

## Why now
Act IV checkpoint drill 4: an audit answer is a change record, so it lands like one.

## Evidence
Every line of the dossier cites the artifact it came from; what the artifacts could not answer is under Gaps.

## If it is wrong
Revert this merge; the artifacts it cites are unchanged.

Refs: #21
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

**Record: prod changes by a robot, and prod changes with a second reviewer, each out of the last ten.**

## Pass criteria

- [ ] All four drills completed; numbers recorded below.
- [ ] No skill merged anything: every merge since the act's last stage is yours, or the robot's on the one subject its template can write:

```sh
git log --first-parent --merges --format='%h  %an  %s' stage-16..
# → every line <you>, or github-actions[bot] with a pin(app-dev) subject
```

- [ ] Zero `kubectl apply`/`edit`/`scale` in drills 2 to 4; prod touched only by PR, and only by a human:

```sh
git log --first-parent --format='%an  %s' stage-16.. -- apps/overlays/prod infrastructure/overlays/prod clusters/prod
# → every line <you>
```

- [ ] The prod rung merged on **both signatures** and by digest: dev's green context, a passing `slo-gate`, and the digest dev's pod ran, now prod's:

```sh
yq '.images[0].digest' apps/overlays/prod/kustomization.yaml
kubectl --context kind-ggp-prod-01 -n ggp get pod -l app.kubernetes.io/name=app \
  -o jsonpath='{.items[0].status.containerStatuses[0].imageID}{"\n"}'
# → the same sha256, in the file and on the node
```

- [ ] The promotion's PR carries its rendered blast radius, one root and two lines, and the robot's carries its two-line diff on one marked file:

```sh
n=$(gh pr list --state merged --search "$(./scripts/commit-by-subject --prefix 'promote(app-prod): app ')" --json number -q '.[0].number')
gh api "repos/{owner}/{repo}/issues/$n/comments" \
  --jq '.[] | select(.body | startswith("<!-- rendered-diff -->")) | .body' | grep -c '<summary>'
# → 1
```

- [ ] The three gates refused on the laptop, in hook order, and every run on `main` since the checkpoint began is green (drill 3, step 4).
- [ ] The platform's ladder is per class and its robot proposes only at the top: three pins, one per class overlay; two standing work items open; any open Renovate PR touches the platform overlay alone:

```sh
yq '.spec.chart.spec.version' infrastructure/overlays/platform/patches/traefik.helmrelease.patch.yaml \
  infrastructure/overlays/dev/patches/traefik.helmrelease.patch.yaml infrastructure/overlays/prod/patches/traefik.helmrelease.patch.yaml
gh issue list --label automation --json number,title,state -q '.[] | "#\(.number)  \(.state)  \(.title)"'
gh pr list --author app/renovate --state open --json number,title,files -q '.[] | "#\(.number)  \(.title)  \([.files[].path] | join(" "))"'
```

```
<version>
---
<version>
---
<version>
#<n>  OPEN  Image automation: the dev pin follows the image policy
#<n>  OPEN  Platform currency: Renovate proposes chart bumps at the platform rung
```

- [ ] The version ladder agrees with its authority, and the versions file's history says which rungs stage 16 took:

```sh
./scripts/check-k8s-aks-parity && ./scripts/check-version-ladder && ./scripts/soak-gate --declared && ./scripts/check-ladder-due
git log --first-parent -3 --format='%h  %s' -- clusters/versions.yaml
```

Both gates all PASS, the soak table printed with its two numbers per ascent, and nothing overdue on the ladder (a `SOAKING` line for prod behind dev is the climb in progress). The log reads the rungs stage 16 took, newest first: `promote(prod)!` always, `promote(dev)!` above it when dev was promoted on platform's soak with the kubectl pin in the same diff, `pin(platform)!` on top when AKS's window offered a minor above platform; promotions below the pin, never the other way round. When platform held, the verdict is on stage 16's work item (`gh issue view 20 --comments`): a ladder with nothing to pin is a pass, not a miss, and this checkpoint requires no pin the window did not offer.

- [ ] The evidence question answered from durable artifacts alone: the author field and the scope for provenance, the PR record for review.
- [ ] The dossier landed under `docs/audits/` by a PR citing `#21`.
- [ ] Every checkpoint the act's stages gate on green on the rebuilt fleet, with the act's objects back from git (drill 1's sweep and the block after it).
- [ ] The config repo tagged `act-4`, the boundary `act-4-drill` rebuilds to, the checkpoint's work item closed and the milestone with it ([using the course §5](../using-the-course.md#5-tags-at-every-boundary)):

```sh
git tag act-4 && git push origin act-4
gh issue close 21 --comment "act-4 tagged" && gh api -X PATCH "repos/{owner}/{repo}/milestones/4" -f state=closed
```

The tag makes the act one range. Read it once: it is the act's change as git holds it, and nothing in it arrived any other way:

```sh
git diff act-3..act-4 --stat
# → the lint config and the three hooks, the workflows (rendered-diff, verify's two new jobs,
#   image-update-pr), infrastructure as base plus three class overlays with a pin each and
#   renovate.json, the image objects, the Receiver and its token on local-01, the digest pins
#   and their policy, the soak file and its gate, the seeded scripts and decisions, the pins the
#   drills moved and the two rungs the ladder climbed, docs/audits: about 70 files
```

| Measure | Value | Date |
|---|---|---|
| Fleet-from-nothing | – | – |
| Event → scan (the push; the interval is the poll's worst case) | – | – |
| Dev rung (robot's merge → green on dev-01) | – | – |
| Prod rung (merge → green on prod-01) | – | – |
| Refusals before push (style, subject, policy) | – | – |
| Red `verify` runs on `main` in the window | – | – |
| Prod changes by a robot, of the last ten | – | – |
| Prod changes with a second reviewer, of the last ten | – | – |

Reference values from a three-cluster kind fleet: fleet-from-nothing ≈410s against Act III's ≈400s, event → scan ≈0.3s from the Receiver's touch (the `requestedAt` annotation) to the scan's log line, dev rung ≈115s, prod rung ≈65s, three refusals, one red run on `main` that was a download failing in an install step rather than a gate, and both evidence numbers zero of ten. Fleet-from-nothing should sit beside Act III's rather than above it, since the two extra controllers and the image objects are a light pull next to the monitoring stack and the same three stamps are timed; event → scan is single-digit seconds against a 300s interval, the number stage 15 measured, and its value is that it is not minutes; the dev rung should read as Act III's dev rung read, because the rung starts at the merge and the robot's CI run sits before it, not inside it; the prod rung likewise, and minutes more when a fresh tag pulls slowly, because the rung is not green until the pod is Ready; the three refusals and the zero reds are counts, not timings; and the two evidence numbers are both zero on a one-person repo, which is the truth and not a gap. Yours come from artifacts, not from this sentence.

## After the checkpoint

- Found a broken step? Fixes to the walkthrough are PRs against the course repo.
- **What "scratch" meant here.** Every kind cluster destroyed; git, the three class root keys and one flag survived. The robot's privilege came back as `--write` on one sync, its key did not: `cluster-sync` minted a new one and the forge shows when. Two things the forge held for the act rather than the clusters, the repository setting that lets Actions open PRs and the robots' standing work items, were never at risk. Act V assumes exactly this fleet, with the robot writing at dev: stage 17 rotates the three root keys the rebuild pays, and the breach rotation drill (the side quest that unlocks after Act V) is where the robot's deploy key is re-minted under time, alongside everything else a stolen clone could hold.
- **What this unlocks.** Two side quests assume this act's machinery: *Migrate a base change* (the expand/contract lifecycle for config, with stage 12's rendered diff showing the shrinking remainder at every step) and *When the X goes red* (the reflexes keyed off a red on `main`: the incident issue, the drafted revert, the paused robot). Both are in the README's side-quest table.

---

**Next:** [17 - Key rotation](../act-5/stage-17.md)
