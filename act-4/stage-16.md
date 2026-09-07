# Stage 16 - The version ladder climbs

[← 15 - The event that arrives (push, not poll)](stage-15.md) · [Walkthrough index](../README.md)

> **Where you are:** the root of the config repo, on `main`. **Starting state:** 15 complete and the fleet live. If it isn't, the previous act's `act-3-drill` rebuilds it from git (git is at HEAD, so everything since comes back with it). **Why here:** the standing procedure for every Kubernetes minor, not a one-off. Run it again every cycle: a rung is promotable the day the rung above has served its declared soak, and the platform pin is due the day AKS offers a minor above it. It closes the act because it is the ladder carrying something that isn't the app.

**Goal:** stage 07 *declared* the ladder. Platform tests next, dev runs current, prod runs stable, pins in `clusters/versions.yaml`. This stage *climbs* it, deliberately: prod promotes onto the minor dev has soaked, then dev onto the minor platform has soaked with the kubectl pin in the same diff, and only then does platform pin a new minor, when AKS offers one. Promote, then pin, one PR and one rebuild per rung. Before the first rung it declares the soak itself, `soak.yaml`, so that "has soaked" is a number a gate holds every promotion to, from git's own dates, and not a feeling. The first rung is the stage's example and always runs; the second is the same shape on the same evidence and is yours to take; the third waits on the calendar. Locally kind can't upgrade in place, so rebuild-per-rung **simulates** the rollout shape; Act VIII does it for real on AKS, where in-place upgrading is precisely what the managed offering is best at, and where in-place is the *point*: it audits your configuration (PDBs, surge headroom, deprecated APIs) on the platform rung instead of in prod.

## Steps

Every step below reads variables the step before it set, so the whole stage runs in one terminal, and the first block turns history expansion off there: three of the subjects below carry `!`, which an interactive bash reads as a history character and refuses before anything runs.

### 1. Read the ladder: what has soaked, and what the authority offers

Two facts decide the rungs. What the rung above has run, and since when, decides a promotion; what AKS's window offers above platform decides the pin ([rule 4.3](../rules.md#43-the-version-policy-follow-the-authority-at-the-pace-kubernetes-sets), declared at stage 07 by `derive-ladder`). The parity gate must be green before anything moves, and the derivation prints the ladder the window implies today:

```sh
set +H   # the '!' subjects below are history characters to an interactive bash
./scripts/check-k8s-aks-parity
ladder=$(./scripts/derive-ladder)
echo "$ladder"
```

```text
== check-k8s-aks-parity: the ladder against AKS's window ==
PASS  prod (1.34) is inside AKS's window (1.36 1.35 1.34)
PASS  dev (1.35) is inside AKS's window (1.36 1.35 1.34)
PASS  platform (1.36) is inside AKS's window (1.36 1.35 1.34)

check-k8s-aks-parity: 3 PASS
AKS support window today: 1.36 1.35 1.34   (source: the AKS release calendar)
  platform  minor 1.36   node_image kindest/node:v1.36.4
  dev       minor 1.35   node_image kindest/node:v1.35.8   (kubectl pins here)
  prod      minor 1.34   node_image kindest/node:v1.34.11
```

A FAIL naming a class that left the window means the deliberate cadence was missed and the window is now forcing the climb; the same three rungs in the same order are the fix, today. Green, capture the rungs before anything is written, because each hands its pin to the next, and read the soak off the versions file's own history (the date a class line last changed is how long that class has run its minor):

```sh
WINDOW=$(./scripts/derive-ladder --window | tail -1)
NEXT=$(echo "$ladder" | awk '$1=="platform" {print $3}'); IMG=$(echo "$ladder" | awk '$1=="platform" {print $5}')
PLAT_OLD=$(yq '.classes.platform.minor' clusters/versions.yaml); PLAT_OLD_IMG=$(yq '.classes.platform.node_image' clusters/versions.yaml)
DEV_OLD=$(yq '.classes.dev.minor' clusters/versions.yaml); DEV_OLD_IMG=$(yq '.classes.dev.node_image' clusters/versions.yaml)
PROD_OLD=$(yq '.classes.prod.minor' clusters/versions.yaml); PROD_OLD_IMG=$(yq '.classes.prod.node_image' clusters/versions.yaml)
DEV_SINCE=$(git log --first-parent -s -1 --format=%cs -L'/^  dev:/,+1:clusters/versions.yaml')
PLAT_SINCE=$(git log --first-parent -s -1 --format=%cs -L'/^  platform:/,+1:clusters/versions.yaml')
echo "rung 1  prod      $PROD_OLD -> $DEV_OLD ($DEV_OLD_IMG); dev has run it since $DEV_SINCE"
echo "rung 2  dev       $DEV_OLD -> $PLAT_OLD ($PLAT_OLD_IMG); platform has run it since $PLAT_SINCE; kubectl $DEV_OLD -> $PLAT_OLD"
echo "rung 3  platform  $PLAT_OLD -> $NEXT ($IMG); AKS's window is $WINDOW"
```

```text
rung 1  prod      1.34 -> 1.35 (kindest/node:v1.35.8); dev has run it since 2026-08-31
rung 2  dev       1.35 -> 1.36 (kindest/node:v1.36.4); platform has run it since 2026-08-31; kubectl 1.35 -> 1.36
rung 3  platform  1.36 -> 1.36 (kindest/node:v1.36.4); AKS's window is 1.36 1.35 1.34
```

Read the three lines against two rules, because they are the whole design. **A rung promotes when the rung above has served its soak**, not when the window forces it. Rung 1 is the promotion this stage always makes, and it is safe by construction: prod moves onto a minor platform and dev have both run, taking dev's image verbatim ([pattern 4](../appendices/patterns.md#4-promotion-is-a-pointer-move): what climbs is the reference, and the artifact it names was soaked one rung up for a whole cycle). Rung 2 is the same move one rung up, due on the same evidence; take it now if platform's soak satisfies you, or leave dev where it is and take it next cycle by the same PR. Both are legal states: between promotions two classes share a minor, which is what a ladder looks like mid-climb, which is always. **Promote before you pin.** The third line is a pin only when its two minors differ; equal, AKS offers nothing above platform and the pin waits (step 5 records that). The order is why one client suffices: promoting first closes the fleet to two minors, so the pin that follows opens it to three, never four, and the kubectl pinned to dev reaches every cluster at every step. Pinning first, platform taking a new minor while prod still runs the oldest, spans four and forces a second client. The window is the deadline the parity gate watches, not the trigger. One check the registry cannot make for you: a node image boots on the kind release that built it, so before a pin, read kind's release notes for the new minor and hold `kind version` to that release or newer.

### 2. Declare the soak, and let the gates hold every promotion to it

"Dev has run it since 2026-08-31" is a date; whether that is long enough was, until now, a feeling. Stage 09's `slo-gate` holds an image to a minimum residency, two minutes by default, from an environment variable nothing reviews, and no number at all exists for a chart or a Kubernetes minor. Declare the soak the way stage 06 declared versions and stage 27 will declare freezes: a file in git, one number per ascent, reviewed like any other change. The values are a walkthrough's, short enough to run the course in a sitting; the comment says what a fleet raises them to.

```sh
cat > soak.yaml <<'EOF'
# The soak per ascent (rule 5.7), two numbers each. min: how long an artifact must have
# run on the rung above before it may climb; scripts/soak-gate holds every promotion to
# it, in the pre-push hook, in CI's pr-record job and in the promote skill. max: how long
# the rung below may lag behind, because past that point the rung above is testing
# against a platform the rung below does not run, and its evidence is no longer about it;
# scripts/check-ladder-due reports every ascent in progress against both and goes red
# past max. Both read the time served from git's own dates (rule 5.8), never a clock.
#
# These are a walkthrough's values, short enough to run the course in a sitting. A fleet
# raises min and tightens max (appendices/take-it-to-production.md in the course). An
# ascent that cannot wait carries a Soak-waived: <reason> trailer, and the gate passes
# it loudly; one that must not happen yet is a freeze in freezes.yaml, which the report
# reads before it goes red.
#
# Entry rungs (an image at dev, a chart or a minor at platform) are pins, not promotions,
# and owe no soak: that is where the artifact starts earning one.
image:
  prod:
    min: 2m
    max: 3d
chart:
  dev:
    min: 1h
    max: 7d
  prod:
    min: 1d
    max: 14d
kubernetes:
  dev:
    min: 1d
    max: 14d
  prod:
    min: 3d
    max: 28d
EOF
./scripts/soak-gate --declared
```

```text
== soak-gate --declared: soak.yaml, the soak per ascent ==
  kubernetes  -> dev   min 1d   max 14d   (served on platform)
  kubernetes  -> prod  min 3d   max 28d   (served on dev)
  chart       -> dev   min 1h   max 7d    (served on platform)
  chart       -> prod  min 1d   max 14d   (served on dev)
  image       -> prod  min 2m   max 3d    (served on dev)
```

The gate reads the time served the way the audit will read it later: it walks the first-parent commits that put the candidate on the rung above and kept it there, and the oldest one's date is the start of the soak ([rule 5.8](../rules.md#58-no-stopwatch-anywhere): a number derived from what git recorded, never one somebody typed). A candidate the rung above is not serving is a FAIL, so a rung skipped cannot pass as a soak. Ask it about the two promotions this stage may make, before either exists:

```sh
./scripts/soak-gate kubernetes prod
./scripts/soak-gate kubernetes dev
```

```text
== soak-gate: kubernetes -> prod, the soak per ascent from git's dates ==
PASS  kubernetes -> prod: 1.35 has run on dev since 2026-08-31 (<n>d <n>h of the 3d required)

soak-gate: 1 PASS
== soak-gate: kubernetes -> dev, the soak per ascent from git's dates ==
PASS  kubernetes -> dev: 1.36 has run on platform since 2026-08-31 (<n>d <n>h of the 1d required)

soak-gate: 1 PASS
```

**The second number bounds the other direction, and it is the one nobody declares.** `min` is what the artifact owes before it climbs. `max` is what the rung below owes: how long prod may run something dev has already left behind, because past that point dev is testing releases against a platform prod does not run, and dev's evidence has quietly stopped being about prod. The Kubernetes ladder has had this bound in versions since stage 07 (each class at most one minor behind the next); charts and images had it in nothing. `check-ladder-due` reads both numbers off git's dates and prints one line per ascent where a rung is ahead of the one below: `SOAKING` until `min` is served, `DUE` from then until `max`, `FAIL` past it, and `FROZEN` when the calendar stage 27 declares covers the rung's paths. Its prefix puts it inside `./scripts/check`, so every stage start and every checkpoint prints what the ladder owes, and an overdue ascent is a red fleet until someone promotes it, waives it or declares the freeze that excuses it. Today every rung serves what the rung above serves:

```sh
./scripts/check-ladder-due
```

```text
== check-ladder-due: what the ladder owes, against soak.yaml ==
OK  nothing is due: every rung serves what the rung above serves

check-ladder-due: 0 ascent(s) in progress, 0 overdue
```

**Outside a stage, this is how the ladder is operated.** A Renovate merge at platform, a robot's pin at dev or a class pin in the versions file starts a clock the report reads. The report runs wherever `./scripts/check` runs: at every stage start here, and on a daily schedule on a fleet, which stage 27 wires beside the freeze calendar the report already reads. A line that reads `DUE` becomes a work item, so the ascent has an owner and a closure rather than a line in a report nobody actions: `./scripts/soak-gate --due --items` opens one per due ascent that has none (idempotent by title, a sub-issue of the standing item that owns the artifact class, labelled `promotion`), and the promotion PR closes it with `Closes: #<n>`. The standing item then reads arrivals, the sub-issues read the ascents, and the versions file's history reads what actually moved. `dora` draws the same line from the other side: soak time up to `max`, queue time past it.

**Deciding not to promote is a decision, and it is recorded the same way.** A release found wanting on dev, one the team will skip and take the next fix instead, is not promoted and is not silently ignored either: close its item with the reason (`gh issue close <n> --comment "Not promoting 41.5.0: <the issue>; waiting for 41.5.1"`), and from then on the report reads that ascent as `HELD` with the item and the reason, green, until dev serves something else and a new clock starts. `--items` never reopens it. Prod then skips the version, the next promotion's history shows the gap, and the closed item says why. A release bad enough to leave dev is a `pr-revert` on the dev pin, forward-only promotion being the rule; the robot's next build replaces it anyway. What a hold does not do is stop the skew: prod is still running what dev left behind, and the `HELD` line carries the date so a hold that outlives the next release is visible for what it is.

A number in a file is policy only where something reads it. Two readers, the same two that hold every other gate ([rule 5.9](../rules.md#59-gates-not-checks---and-ci-is-a-backstop-that-never-fires): hooks first, CI the backstop). The pre-push hook from stage 11 gains the gate as a fourth line, judging the branch against `origin/main`, so a promotion that has not soaked never leaves your machine:

```sh
cat > hooks/pre-push <<'EOF'
#!/usr/bin/env bash
# Exactly CI's jobs - a push that would fail CI fails here first, for free.
# Every gate runs and then the hook fails, as CI shows every job: a hook that
# stops at the first red hides the second, and one that just runs three gates
# in a row returns only the last one's verdict.
set -uo pipefail
fail=0
./scripts/style-gate || fail=1
./scripts/policy-gate || fail=1
./scripts/commit-gate --docs || fail=1
./scripts/soak-gate origin/main HEAD || fail=1
exit "$fail"
EOF
```

And CI's `pr-record` job, the one that already judges the title and the work item, judges the soak on the PR's diff with the title and body as the record (the `Soak-waived:` trailer lives in the body, and the title says when a change is a revert or a break, which owe no soak), and again on the push to `main` with the merge commit as the record. The gate reads dates, so the job's checkout needs the history it has been skipping (`fetch-depth: 0`), and the base branch arrives as data through `env:`, never inlined (`yq` writes the file; it re-indents lists, so `style-fix` follows it, as [rule 3.5](../rules.md#35-the-tool-writes-the-file) requires):

```sh
cat > /tmp/pr-record.sh <<'EOF'
# on a PR: the title and body that WILL become the merge commit
# on a push: the subject and body that a merge (or a robot) just produced,
#            whose work item the merge may already have closed (--landed)
# either way: every promotion pointer the change moves has served its soak (soak.yaml)
if [ -n "$TITLE" ]; then
  ./scripts/commit-gate --subject "$TITLE" "$BODY"
  ./scripts/issue-gate "$BODY"
  printf '%s\n\n%s\n' "$TITLE" "$BODY" > "$RUNNER_TEMP/record"
  ./scripts/soak-gate --record "$RUNNER_TEMP/record" "origin/$BASE" HEAD
else
  git log -1 --format=%B > "$RUNNER_TEMP/message"
  ./scripts/commit-gate --file "$RUNNER_TEMP/message"
  ./scripts/issue-gate --landed --file "$RUNNER_TEMP/message"
  ./scripts/soak-gate --record "$RUNNER_TEMP/message" HEAD^1 HEAD
fi
EOF
yq -i '.jobs.pr-record.steps[0].with."fetch-depth" = 0 |
       .jobs.pr-record.steps[1].env.BASE = "${{ github.base_ref }}" |
       .jobs.pr-record.steps[1].run = load_str("/tmp/pr-record.sh")' .github/workflows/verify.yaml
./scripts/style-fix .github/workflows/verify.yaml
git diff .github/workflows/verify.yaml
```

Seven added lines among the context, nothing removed: the checkout gains `fetch-depth: 0`, the step gains `BASE`, the script gains one comment, the record line and two gate lines.

```text
+      with:
+        fetch-depth: 0
+        BASE: ${{ github.base_ref }}
+        # either way: every promotion pointer the change moves has served its soak (soak.yaml)
+          printf '%s\n\n%s\n' "$TITLE" "$BODY" > "$RUNNER_TEMP/record"
+          ./scripts/soak-gate --record "$RUNNER_TEMP/record" "origin/$BASE" HEAD
+          ./scripts/soak-gate --record "$RUNNER_TEMP/message" HEAD^1 HEAD
```

Then the PR; its own push runs the new hook, and the gate finds no promotion pointer in the diff, which is the verdict a policy change should get:

```sh
git add soak.yaml hooks/pre-push .github/workflows/verify.yaml
./scripts/pr-open policy/20/soak "policy(ci): declare the soak per ascent; every promotion is judged against it" <<'EOF'
## What is moving
soak.yaml at the root: the soak an artifact owes on the rung above before it climbs, per kind and target rung. scripts/soak-gate reads it, and reads the time served from git's dates. The pre-push hook and CI's pr-record job run the gate on every change and judge only the promotion pointers a change moves; a Soak-waived: trailer passes a failing verdict, in the record.

## Why now
Stage 16 promotes prod on dev's soak. A soak nobody declared is a feeling; declared, it is a gate with a number, in the same file family as the freeze calendar.

## Evidence
soak-gate --declared prints the table; soak-gate kubernetes prod and kubernetes dev both PASS on today's history, so the two promotions this stage makes are owed nothing.

## If it is wrong
Revert cleanly: the file and the two edits carry no state.

Refs: #20
EOF
```

```sh
gh pr checks --watch --fail-fast \
&& gh pr merge --merge --delete-branch \
&& git switch main \
&& git pull
```

`pr-record` is the check to read on this PR: its log ends with `OK  no promotion pointer moves in this change - nothing to soak`, the gate's word for a change that is not a promotion.

### 3. Rung 1: prod promotes onto the minor dev has soaked

One PR, one line pair, then the rebuild (versions are pins, clusters are replaceable). Prod moves only onto a minor that platform *and* dev have already run, and it takes dev's image verbatim.

**Note the `!`.** In this repo it does not mean "breaks the API." There is no API. It means **"reverting this will not restore the previous state"** ([rule 9](../appendices/commit-convention.md#the-nine-deciding-rules)). This rung is *rebuilt*, not upgraded in place: reverting the pin in `versions.yaml` leaves the file disagreeing with a live cluster that no longer exists in its old form, and nothing in git can put it back. Which is why the marker **requires a `Roll-forward:` trailer**, and `pr-open` refuses the subject without one. A warning with no instruction is the least useful thing a commit can carry at 3am. That is also why [`revert-gate`](../act-5/stage-20.md) prints that trailer back at you if you ever try to undo one. Most commits are not this; a pin move, a replica count, a policy rule all revert cleanly, and marking them dilutes the signal until nobody reads it.

```sh
yq -i ".classes.prod.minor = \"$DEV_OLD\" | .classes.prod.node_image = \"$DEV_OLD_IMG\"" clusters/versions.yaml
git add clusters/versions.yaml
./scripts/pr-open promote/20/prod-$DEV_OLD "promote(prod)!: kubernetes $DEV_OLD" <<EOF
## What is moving
The prod class pin, $PROD_OLD to $DEV_OLD ($DEV_OLD_IMG, the image dev ran).

## Why now
Deliberate, not forced: dev has run $DEV_OLD since $DEV_SINCE, green at every checkpoint since, and platform ran it the cycle before. AKS's window ($WINDOW) still holds $PROD_OLD; the climb does not wait for it to leave.

## Evidence
soak-gate kubernetes prod PASS on the soak soak.yaml declares; check-k8s-aks-parity green for prod on the merge; checkpoint-07 green on the rebuilt cluster.

## If it is wrong
The cluster is rebuilt, not upgraded in place, so a revert of this line alone restores nothing. See the trailer.

Roll-forward: pin the previous minor ($PROD_OLD, $PROD_OLD_IMG) and rebuild prod again (CLASS=prod ./scripts/cluster-up). Reverting this commit alone leaves versions.yaml disagreeing with a live cluster.

Refs: #20
EOF
```

The push ran the hook, and the hook ran the gate on the one pointer this diff moves; it printed the same PASS line step 2 did. Read the PR; when the diff is the two lines the body claims:

```sh
gh pr checks --watch --fail-fast \
&& gh pr merge --merge --delete-branch \
&& git switch main \
&& git pull
```

```sh
source ./env.sh
CLUSTER_NAME=ggp-prod-01 ./scripts/cluster-down
CLASS=prod CLUSTER_NAME=ggp-prod-01 HTTP_PORT=8082 HTTPS_PORT=8445 ./scripts/cluster-up
./scripts/cluster-sync clusters/prod/prod-01 --context kind-ggp-prod-01
kubectl --context kind-ggp-prod-01 -n flux-system create secret generic sops-age \
  --from-file=age.agekey=$HOME/.config/gitops-golden-path/age/prod.agekey
echo -n "waiting for the rebuilt rung to converge (checkpoint-07 passes; the monitoring stack is a heavy pull; up to 10m) "
for i in $(seq 1 40); do ./scripts/checkpoint-07 >/dev/null 2>&1 && break; printf .; sleep 15; done; echo
./scripts/check-version-ladder && ./scripts/checkpoint-07
```

The wait is the same one every act checkpoint runs after a rebuild: the sops-age key can only exist after Flux is installed, so the first reconcile of `cluster-secrets` fails on purpose and its dependants wait for the retry; a gate run before that retry reads the failure, not the rung. `check-version-ladder` all PASS with prod and dev on one minor: the ladder mid-climb, not a stretched one.

### 4. Rung 2: dev promotes, with the kubectl pin in the same diff

Take this rung when platform's soak satisfies you; the stage is complete without it, and it is the same PR next cycle. The binding corollary from stage 07, now exercised: dev's bump moves the fleet's middle, so **the kubectl pin bumps in the same PR**, one diff, both facts. Dev takes the image platform ran, verbatim:

```sh
yq -i ".classes.dev.minor = \"$PLAT_OLD\" | .classes.dev.node_image = \"$PLAT_OLD_IMG\" | .kubectl = \"$PLAT_OLD\"" clusters/versions.yaml
git add clusters/versions.yaml
./scripts/pr-open promote/20/dev-$PLAT_OLD "promote(dev)!: kubernetes $PLAT_OLD, kubectl rides the same diff" <<EOF
## What is moving
The dev class pin, $DEV_OLD to $PLAT_OLD ($PLAT_OLD_IMG, the image platform ran for a whole cycle), and the kubectl pin with it: the middle rung is the only client that reaches the whole fleet.

## Why now
Prod has moved up to $DEV_OLD, and platform has run $PLAT_OLD since $PLAT_SINCE. Dev promotes on that soak, before the window asks.

## Evidence
soak-gate kubernetes dev PASS on the soak soak.yaml declares; check-version-ladder after the rebuild: the pinned and installed kubectl equal the dev class, every rung within one minor of it.

## If it is wrong
The cluster is rebuilt, not upgraded in place, so a revert of this line alone restores nothing. See the trailer.

Roll-forward: pin the previous minor ($DEV_OLD, $DEV_OLD_IMG) and rebuild dev again (CLASS=dev ./scripts/cluster-up), then re-install the kubectl the gate names.

Refs: #20
EOF
```

Read it; when the diff is the three lines the body claims:

```sh
gh pr checks --watch --fail-fast \
&& gh pr merge --merge --delete-branch \
&& git switch main \
&& git pull
```

Install the newly pinned kubectl (the gate hands out the exact command when it fails), then rebuild dev:

```sh
./scripts/check-version-ladder || true   # read its install prescription, run it, re-run until green
```

```text
FAIL  installed kubectl matches the pin  [have 1.35 at <path>/kubectl, want 1.36.x - install: curl -Lo ~/.local/bin/kubectl https://dl.k8s.io/release/$(curl -sL https://dl.k8s.io/release/stable-1.36.txt)/bin/linux/amd64/kubectl && chmod +x ~/.local/bin/kubectl]
```

```sh
source ./env.sh
CLUSTER_NAME=ggp-dev-01 ./scripts/cluster-down
CLASS=dev CLUSTER_NAME=ggp-dev-01 HTTP_PORT=8081 HTTPS_PORT=8444 ./scripts/cluster-up
./scripts/cluster-sync clusters/dev/dev-01 --context kind-ggp-dev-01
kubectl --context kind-ggp-dev-01 -n flux-system create secret generic sops-age \
  --from-file=age.agekey=$HOME/.config/gitops-golden-path/age/dev.agekey
echo -n "waiting for the rebuilt rung to converge (checkpoint-07 passes; the monitoring stack is a heavy pull; up to 10m) "
for i in $(seq 1 40); do ./scripts/checkpoint-07 >/dev/null 2>&1 && break; printf .; sleep 15; done; echo
./scripts/check-version-ladder && ./scripts/checkpoint-07
```

### 5. Rung 3: platform pins the new minor, when AKS offers one

The pin is due only when step 1's third line shows two different minors. Ask, so the decision is the file's and not yours:

```sh
[ "$NEXT" != "$PLAT_OLD" ] && echo "pin: platform $PLAT_OLD -> $NEXT ($IMG)" || echo "no pin: AKS's window ($WINDOW) offers nothing above $PLAT_OLD"
```

```text
no pin: AKS's window (1.36 1.35 1.34) offers nothing above 1.36
```

**No pin.** Record the verdict on the work item, so the next reader of the issue knows why platform held, and go to [Stop & measure](#stop--measure):

```sh
gh issue comment 20 --body "Platform holds $PLAT_OLD: AKS's window ($WINDOW) offers nothing above it. The pin is a new work item when the window moves."
```

**A pin.** Read the commit type carefully: **`pin(platform)`, not `promote(platform)`.** This is the ladder's most easily inverted idea. The [convention](../appendices/commit-convention.md) uses `pin` for a version *arriving* at its entry rung and `promote` for one *climbing*. **The entry rung is per artifact class, not a fixed cluster**. Application images enter at dev (stage 14's robot); Kubernetes minors and charts enter at **platform**, because platform is the rung nobody misses. So the two commits above were promotions and this one is an arrival, and `git log --first-parent --basic-regexp --grep='^promote('` is the honest answer to "what has ever been deliberately advanced." That answer quietly becomes wrong if you type this one `promote`. An arrival owes no soak, and the gate says so on the push (`NOTE  kubernetes -> platform: the entry rung, a pin`). Hold `kind version` to the release that built `$IMG` first (step 1's last sentence), then:

```sh
yq -i ".classes.platform.minor = \"$NEXT\" | .classes.platform.node_image = \"$IMG\"" clusters/versions.yaml
git add clusters/versions.yaml
./scripts/pr-open pin/20/platform-$NEXT "pin(platform)!: kubernetes $NEXT" <<EOF
## What is moving
The platform class pin, $PLAT_OLD to $NEXT ($IMG). The new minor enters at the cluster nobody misses, last, with dev and prod already one rung up, so the fleet spans three minors after this and not four.

## Why now
AKS made $NEXT available: derive-ladder's platform row is this pin.

## Evidence
check-k8s-aks-parity green for every class on the merge; the ladder gate and checkpoint-07 after the rebuild.

## If it is wrong
The cluster is rebuilt, not upgraded in place, so a revert of this line alone restores nothing. See the trailer.

Roll-forward: pin the previous minor ($PLAT_OLD, $PLAT_OLD_IMG) and rebuild again (CLASS=platform ./scripts/cluster-up). Reverting this commit alone leaves versions.yaml disagreeing with a live cluster.

Refs: #20
EOF
```

Read it; when the diff is the two lines the body claims:

```sh
gh pr checks --watch --fail-fast \
&& gh pr merge --merge --delete-branch \
&& git switch main \
&& git pull
```

```sh
source ./env.sh
CLUSTER_NAME=ggp-local-01 ./scripts/cluster-down
CLASS=platform CLUSTER_NAME=ggp-local-01 HTTP_PORT=8080 HTTPS_PORT=8443 ./scripts/cluster-up
# --write: stage 14 gave this cluster's key push access, and a rebuilt cluster mints a new key
./scripts/cluster-sync clusters/platform/local-01 --context kind-ggp-local-01 --write
kubectl --context kind-ggp-local-01 -n flux-system create secret generic sops-age \
  --from-file=age.agekey=$HOME/.config/gitops-golden-path/age/local-01.agekey
```

Note what you did *not* have to remember: stage 14's two extra controllers came back on their own, because they live in the merged `gotk-components.yaml` and the cluster syncs itself from it, and stage 15's Receiver and its token came back with `cluster-secrets`. The one thing git cannot carry is the key's write access. A credential is imperative by nature, and `--write` is the whole of that residue, named on the line.

Gate, after the bounded wait:

```sh
echo -n "waiting for the rebuilt rung to converge (checkpoint-07 passes; the monitoring stack is a heavy pull; up to 10m) "
for i in $(seq 1 40); do ./scripts/checkpoint-07 >/dev/null 2>&1 && break; printf .; sleep 15; done; echo
./scripts/check
CTX=kind-ggp-local-01 ./scripts/checkpoint-06 && ./scripts/checkpoint-07
```

`check-version-ladder` and `check-k8s-aks-parity` both all PASS: three minors again, one rung up, every class inside the window, and `live ggp-local-01 runs its class pin (<new minor>)`.

**Read the cadence, because it is the lesson.** The stage promoted on soak and pinned on availability, two different clocks, and never let the window decide either. A team that waits for the parity gate to go red is on the slow path: it moves prod on the day its minor loses support, the worst day to learn anything, and it moves three rungs in one sitting. The deliberate path moves one rung whenever the rung above has served its soak, by the same one-line PR, and the soak is a number in git that a gate holds the PR to, so the window is a deadline the fleet is always ahead of. Both keep the two constraints that matter, each class at most one minor behind the next and every class inside the window; only one of them gets to choose the day.

## Stop & measure

- [ ] The soak is declared, and the gate reads it:

```sh
./scripts/soak-gate --declared
```

```text
== soak-gate --declared: soak.yaml, the soak per ascent ==
  kubernetes  -> dev   1d    (served on platform)
  kubernetes  -> prod  3d    (served on dev)
  chart       -> dev   1h    (served on platform)
  chart       -> prod  1d    (served on dev)
  image       -> prod  2m    (served on dev)
```

- [ ] Every parity gate and the ladder rule agree with the new pins:

```sh
./scripts/check
```

`check-version-ladder` and `check-k8s-aks-parity` both all PASS: every class inside AKS's window, each class within one minor of the pinned kubectl, and every live cluster on its class pin. After rung 1 alone prod and dev share a minor; that is a ladder mid-climb, not a stretched one. `check-ladder-due` is green either way: after rung 2 it reads prod as `SOAKING` behind dev with the date it becomes promotable, the climb in progress rather than overdue.

- [ ] The fleet is green on the rebuilt rungs:

```sh
./scripts/checkpoint-07
```

`checkpoint-07: 12 passed, 0 failed`.

- [ ] The versions file's history is the upgrade audit:

```sh
git log --first-parent --format='%h  %s' stage-15.. -- clusters/versions.yaml
```

```text
<sha>  promote(prod)!: kubernetes <minor> (#<n>)
```

One line per rung taken, newest first: `promote(prod)!` always, `promote(dev)!` above it when rung 2 was taken, `pin(platform)!` on top when the window allowed rung 3. Promotions below, the pin on top, never the other way round: the timely-remediation evidence an auditor asks for, generated by doing the work, and the order is part of the evidence.

Tag the boundary ([using the course §5](../using-the-course.md#5-tags-at-every-boundary)):

```sh
git tag stage-16 \
&& git push origin stage-16 \
&& gh issue close 20 --comment "stage-16 tagged"
```

## Troubleshooting

| Symptom | Likely cause | Fix |
|---|---|---|
| Step 1's third line shows the same minor twice | AKS's window offers nothing above platform | Not a failure: rungs 1 and 2 are the stage; step 5 records the verdict, and the pin is a new work item when the window moves |
| `check-k8s-aks-parity` FAIL naming a class that left the window | The deliberate cadence was missed and the window is now forcing the climb | The same three rungs in the same order, today; `./scripts/check` keeps saying so until prod moves |
| `soak-gate` FAIL: `has run on dev for <served> of the <required> required` | The rung above has not served the declared soak | Wait until the date the gate names, or carry a `Soak-waived: <reason>` trailer in the body; the gate passes it and says so in the record |
| `./scripts/check` red on `check-ladder-due`: `<artifact> overdue since <date>` | The rung below has lagged past `max`, so the rung above's evidence is no longer about it | Promote it by the same one-line PR (`soak-gate --due --items` opens its work item), waive with the trailer, or declare the freeze that excuses it; the line names the date |
| The report reads `HELD` for an ascent you meant to promote | A closed item carries that ascent's exact title, so the report takes it as the decision | Reopen the item (`gh issue reopen <n>`) and the line returns to what the dates say |
| `soak-gate --due --items` prints `could not open an item` | `gh` is not authenticated, or the standing item's title was changed | `gh auth status`; the parent is found by its title, `Platform currency` or `Image automation` |
| `soak-gate` FAIL: `dev is not serving <candidate>` | The promotion names something the rung above never ran, or ran and moved past | A promotion moves what the rung above serves; read the pointer there and promote that |
| The pre-push hook refuses a promotion you meant to waive | The trailer is not in the body handed to `pr-open`, which is the commit the hook reads | Put `Soak-waived: <reason>` in that body: `pr-open` commits it, the hook reads it off the commit, and CI reads it off the PR |
| `derive-ladder` stops naming the calendar page | The scrape broke: the page changed shape | Read the window off the page it names, and file the fix against the script; never type a minor from memory |
| `kind create cluster` fails on the new image at kubeadm config, or the node never joins | The image was built by a newer kind release than the one installed (1.37 dropped the kubeadm config version older kinds emit) | Install the kind release whose notes list the image, then rebuild |
| `bash: !: unrecognized history modifier`, then a syntax error, before `pr-open` prints anything | The `!` in the subject is a history character to an interactive bash; nothing ran, the edit is still staged | `set +H` (step 1's first line), then the same block again |
| `pr-open` refuses the subject: `'!' without a Roll-forward: trailer` | The body's trailer line was edited away | The trailer is the instruction a 3am revert needs; put it back |
| kubectl errors against platform mid-climb | The climb pinned first: platform took the new minor while prod still ran the oldest, and the fleet spans four minors | Promote first (this stage's order); until prod moves, a side-by-side client: `curl -Lo ~/.local/bin/kubectl-$NEXT "https://dl.k8s.io/release/$(curl -sL https://dl.k8s.io/release/stable-$NEXT.txt)/bin/linux/amd64/kubectl" && chmod +x ~/.local/bin/kubectl-$NEXT` |
| Robot stopped after the platform rebuild | `cluster-sync` run without `--write`, the new key is read-only | Re-run it with `--write` (step 5); the controllers themselves came back from git |
| New cluster never goes Ready | The rebuilt node joined a fleet already at the inotify budget | Stage 07 step 1's sysctl block; `scripts/cluster-up` warns when it can tell |
| `cluster-secrets` red after a rebuild | The sops-age root key step skipped (the era-aware IOU) | Each rung's rebuild block recreates it from the class keyfile |
| `checkpoint-07` red on the rebuilt rung straight after the rebuild: `app-<class> Ready [got: False]`, the app pin `cluster: ?`, HTTP 000 on its port | The gate ran before `cluster-secrets` retried after the key landed, so the stamps behind it had not reconciled yet | The wait loop in the rebuild block, then the gates again; `flux reconcile kustomization app-<class> --context kind-ggp-<cluster>` turns the interval into seconds |

## What you learned

Upgrades are promotions: a minor climbs the same ladder a pin move does, one reviewed line per rung, on the rung above's soak rather than the calendar's deadline, and the soak is a number declared in git that a gate holds every promotion to, from git's own dates. Promote first and pin last, so the fleet never spans more than the pinned client reaches and the new minor enters where failure is cheapest, with the client-tooling pin riding the middle rung's diff. The window is a deadline the parity gate watches, and the versions file's git history *is* the patching audit. On AKS the mechanics change (in-place, upgrade channels); the shape is exactly this: prod up, dev up, then platform takes the new minor, evidence per rung.

---

**Next:** [Act IV checkpoint](act-checkpoint.md)
