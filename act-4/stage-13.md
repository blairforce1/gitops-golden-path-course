# Stage 13 - Platform promotion (change the ingress version)

[← 12 - Rendered diff (blast radius on every PR)](stage-12.md) · [Walkthrough index](../README.md)

> **Where you are:** the root of the config repo, on `main`. **Starting state:** 12 complete and the fleet live. If it isn't, the previous act's `act-3-drill` rebuilds it from git (git is at HEAD, so everything since comes back with it). **Why here:** it restructures `infrastructure/`, which stages 08–09 describe in its pre-restructure shape, so it waits until they are verified. Rehearse the rails while Traefik-by-Ingress is what's on them: the Ingress→Gateway API migration in Act VIII moves this layer.

**Goal:** make "the platform is a workload too" ([rule 5.11](../rules.md#511-the-platform-is-a-workload)) mechanically true. (Terminology, once per page: a *stamp* is a Flux `Kustomization` CR; a cluster's *binding* is its `clusters/<class>/<cluster>/resources/` folder, the stamps it runs; the *ladder* is the platform→dev→prod order, enforced by PR discipline and evidence, not by any controller.) Today a Traefik chart bump in the shared `infrastructure/` tree hits all three clusters within one reconcile interval of merging: there is no ladder for the platform. This stage gives the platform the same shape the app already has (base + class overlays, the pin per class), rides a real change up the ladder platform→dev→prod, and then hands the pins to **Renovate** so currency arrives as reviewed PRs.

**The order of the worked example:** the *first* promoted change is the restructure itself, proven render-identical, then carried cluster by cluster exactly as a risky change would be. That is the point, not a cop-out: the rails get proven on a zero-risk change, so the first real bump rides rails you have already watched work. Whether that first real bump is yours (step 5) or Renovate's (step 6) depends on the chart index the day you run this:

```sh
curl -s https://traefik.github.io/charts/index.yaml | yq '.entries.traefik[0].version'
yq '.spec.chart.spec.version' infrastructure/traefik/resources/traefik.helmrelease.yaml
```

Two different numbers: step 5 rides the bump up the ladder by hand, and Renovate arrives to a fleet already current. The same number: skip step 5, and Renovate's first PR is the first real bump.

## Steps

### 1. Capture the baseline - the render, and the release each cluster runs

The restructure must change nothing any cluster receives, and the proof has two halves: the render (byte-identical before and after) and the Helm release revision on each cluster (unmoved, because an identical render is a no-op upgrade). Capture both now:

```sh
kustomize build infrastructure > /tmp/infra-before.yaml
for ctx in kind-ggp-local-01 kind-ggp-dev-01 kind-ggp-prod-01; do
  kubectl --context $ctx -n traefik get helmrelease traefik \
    -o jsonpath="$ctx: chart {.status.history[0].chartVersion} release revision {.status.history[0].version}{'\n'}"
done | tee /tmp/infra-revisions-before.txt
```

Three lines, one per cluster, each naming the chart version the base pins and a small integer: the Helm release revision, which moves only when Helm installs something different.

### 2. Restructure: base + class overlays, version pinned per class

The same shape as `apps`: base holds the resources, each class overlay holds *its* pin as a patch. During the transition the base keeps its version (so clusters still bound to the old path render unchanged); an explicit root kustomization makes the old path deliberate rather than controller-guessed. The PR that lands this (step 3's first) is the first half of [the restructure-first pattern](../appendices/patterns.md#2-restructure-first-then-change): it changes the shape and nothing else, the four renders prove it, and every PR after it moves one pointer or one value on one rung. The pin the patches carry is read off the base, never typed:

```sh
v=$(yq '.spec.chart.spec.version' infrastructure/traefik/resources/traefik.helmrelease.yaml)
mkdir -p infrastructure/base
git mv infrastructure/traefik infrastructure/base/traefik
rm infrastructure/kustomization.yaml   # stage 09 created this root; kustomize create refuses overwrite
# explicit-selection root: old-path clusters see base only, never the overlays
(cd infrastructure && kustomize create --resources base/traefik)

for class in platform dev prod; do
  mkdir -p infrastructure/overlays/$class/patches
  cat > infrastructure/overlays/$class/patches/traefik.helmrelease.patch.yaml <<EOF
apiVersion: helm.toolkit.fluxcd.io/v2
kind: HelmRelease
metadata:
  name: traefik
  namespace: traefik
spec:
  chart:
    spec:
      chart: traefik
      version: "$v"
      sourceRef:
        kind: HelmRepository
        name: traefik
EOF
  (cd infrastructure/overlays/$class \
   && kustomize create --resources ../../base/traefik \
   && kustomize edit add patch --path patches/traefik.helmrelease.patch.yaml)
done
```

Read the patch before moving on: it's a strategic-merge patch that is *also a syntactically complete HelmRelease fragment*, with chart, version, and sourceRef all present. That redundancy is deliberate twice over: the overlay file states exactly what its class runs without a trip to base, and Renovate's flux manager (step 6) can parse it as the update site.

Gate: all four renders (old path, three overlays) are byte-identical to the baseline. The restructure changes *shape*, not *state*:

```sh
for p in infrastructure infrastructure/overlays/platform infrastructure/overlays/dev infrastructure/overlays/prod; do
  diff <(kustomize build $p) /tmp/infra-before.yaml >/dev/null && echo "PASS  $p renders unchanged" || echo "FAIL  $p diverged"
done
```

Four PASS lines. Nothing is committed yet; the tree carries the restructure and step 3's PR carries it to `main`.

### 3. Rung 1 - platform: the shape first, then its own binding move, two PRs

The shape lands on its own. No binding moves, so every cluster still renders `./infrastructure`, which now selects base alone, and the render of every root a cluster consumes is the byte-identical one step 2 proved. That is the whole content of the PR, and its type says so: `refactor`, the type of a change that renders empty ([base is sacred](../appendices/patterns.md#3-base-is-sacred)).

```sh
git add infrastructure
./scripts/pr-open refactor/17/infra-class-overlays "refactor(infrastructure): base and class overlays, every binding unchanged" <<'EOF'
## What is moving
infrastructure/ becomes base/ plus three class overlays, each carrying its own chart pin as a patch. No binding moves: every cluster still renders ./infrastructure, which now selects base alone.

## Why now
The platform had no ladder: a chart bump in the shared tree reached all three clusters within one interval. The shape that gives it one lands first, on a change that renders identically everywhere.

## Evidence
Step 2's gate: all four roots byte-identical to the pre-restructure render. Nothing any cluster receives changes.

## If it is wrong
Revert this merge; the old tree comes back and, again, nothing rendered changes.

Refs: #17
EOF
```

Read the diff (the moved files, the new ones, the root's one changed line). Then read the rendered-diff comment stage 12 left, from the terminal: it is posted by the last step of the `render` job, so it exists once the checks are green.

```sh
gh pr checks --watch --fail-fast
n=$(gh pr view refactor/17/infra-class-overlays --json number -q .number)
gh api "repos/{owner}/{repo}/issues/$n/comments" \
  --jq '.[] | select(.body | startswith("<!-- rendered-diff -->")) | .body' \
  | grep -E '<summary>|^No rendered'
```

```
No rendered change - this PR alters nothing any cluster receives.
```

No binding points at an overlay yet, so the new folders are not roots, and the one root every cluster consumes renders as before. That is step 2's proof seen from the reviewer's chair, and the empty diff the pattern asks for. The checks are already green, so merge:

```sh
gh pr merge --merge --delete-branch \
&& git switch main \
&& git pull
```

Every cluster reconciles the new revision and applies nothing, which is the quietest possible success. Now the pointer, and only the pointer: platform is the entry rung for platform changes, so it moves first.

```sh
yq -i '.spec.path = "./infrastructure/overlays/platform"' \
  clusters/platform/local-01/resources/infrastructure.kustomization.yaml
git add clusters/platform
./scripts/pr-open bind/17/infra-platform-rung "bind(local-01): infrastructure to the platform class overlay" <<'EOF'
## What is moving
One line: local-01's infrastructure stamp re-aims at the platform class overlay.

## Why now
The shape is on main and rendered empty; platform is the rung platform changes enter at.

## Evidence
Step 2's gate for the platform overlay. Step 1's release revision, to be re-read after the merge.

## If it is wrong
Revert this merge; the stamp returns to the old path, which never stopped rendering.

Refs: #17
EOF
```

Read the diff (one line), then the comment:

```sh
gh pr checks --watch --fail-fast
n=$(gh pr view bind/17/infra-platform-rung --json number -q .number)
gh api "repos/{owner}/{repo}/issues/$n/comments" \
  --jq '.[] | select(.body | startswith("<!-- rendered-diff -->")) | .body' \
  | grep -E '<summary>|^No rendered'
```

Two `<summary>` lines: the platform cluster's root (`clusters/platform/local-01`, the binding line itself) and `infrastructure/overlays/platform` with the whole render as additions, because that root did not exist on the base side. `infrastructure` is absent, because its render did not change. Merge, then verify the stamp goes green on the new path and the release revision does not move:

```sh
gh pr merge --merge --delete-branch \
&& git switch main \
&& git pull
flux reconcile kustomization infrastructure --with-source --context kind-ggp-local-01
kubectl --context kind-ggp-local-01 -n flux-system get kustomization infrastructure \
  -o jsonpath='{.spec.path} Ready={.status.conditions[?(@.type=="Ready")].status}{"\n"}'
kubectl --context kind-ggp-local-01 -n traefik get helmrelease traefik \
  -o jsonpath="kind-ggp-local-01: chart {.status.history[0].chartVersion} release revision {.status.history[0].version}{'\n'}"
```

Expected: `./infrastructure/overlays/platform Ready=True`, and the helmrelease line equal to the platform line in `/tmp/infra-revisions-before.txt`.

### 4. Rungs 2 and 3 - dev, then prod, each on the previous rung's evidence

Same move, one cluster per PR, prod only after dev's green context: the stage-07 discipline, now applied to the platform's own plumbing.

```sh
yq -i '.spec.path = "./infrastructure/overlays/dev"' \
  clusters/dev/dev-01/resources/infrastructure.kustomization.yaml
git add clusters/dev
./scripts/pr-open bind/17/infra-dev-rung "bind(dev-01): infrastructure to the dev class overlay" <<'EOF'
## What is moving
One line: dev-01's infrastructure stamp re-aims at the dev class overlay.

## Why now
The platform rung is green on its overlay with its release revision unmoved (step 3).

## Evidence
Step 2's gate for the dev overlay; the platform rung's Ready=True and unchanged revision.

## If it is wrong
Revert this merge; the old path still renders base.

Refs: #17
EOF
```

```sh
gh pr checks --watch --fail-fast \
&& gh pr merge --merge --delete-branch \
&& git switch main \
&& git pull
flux reconcile kustomization infrastructure --with-source --context kind-ggp-dev-01
kubectl --context kind-ggp-dev-01 -n flux-system get kustomization infrastructure \
  -o jsonpath='{.spec.path} Ready={.status.conditions[?(@.type=="Ready")].status}{"\n"}'
```

The prod rung also retires the base pin, so it is typed by its payload, not by the pointer move:

Prod is two PRs, and the order is not a style choice. First the pointer, and only the pointer:

```sh
yq -i '.spec.path = "./infrastructure/overlays/prod"' \
  clusters/prod/prod-01/resources/infrastructure.kustomization.yaml
git add clusters/prod
./scripts/pr-open bind/17/infra-prod-rung "bind(prod-01): infrastructure to the prod class overlay" <<'EOF'
## What is moving
One line: prod-01's infrastructure stamp re-aims at the prod class overlay.

## Why now
Dev is green on its overlay with its release revision unmoved.

## Evidence
Step 2's gate for the prod overlay; dev's Ready=True on its overlay.

## If it is wrong
Revert this merge: prod returns to the old path, which still renders base with its pin.

Refs: #17
EOF
```

```sh
gh pr checks --watch --fail-fast \
&& gh pr merge --merge --delete-branch \
&& git switch main \
&& git pull
flux reconcile kustomization infrastructure --with-source --context kind-ggp-prod-01
kubectl --context kind-ggp-prod-01 -n flux-system get kustomization infrastructure \
  -o jsonpath='{.spec.path} Ready={.status.conditions[?(@.type=="Ready")].status}{"\n"}'
```

`./infrastructure/overlays/prod Ready=True`. Now nothing reads the old root, so the pin base still carries is a second authority nobody reads, and it goes. This is a base edit, so read what base accepts before opening it: the render of every root any cluster consumes must not change, and here it cannot, because every class overlay already supplies its own version.

```sh
yq -i 'del(.spec.chart.spec.version)' infrastructure/base/traefik/resources/traefik.helmrelease.yaml
git add infrastructure/base
./scripts/pr-open refactor/17/infra-base-pin "refactor(infrastructure): base pin retired" <<'EOF'
## What is moving
base loses its chart version: from here each class overlay is the only pin authority for its class.

## Why now
No binding consumes base directly once prod moved, so a pin there is a second authority nobody reads.

## Evidence
No root any cluster consumes renders differently: the rendered-diff comment says so.

## If it is wrong
Revert this merge; base regains a pin nothing reads.

Refs: #17
EOF
```

The comment is the evidence the body cites, so read it before the merge:

```sh
gh pr checks --watch --fail-fast
n=$(gh pr view refactor/17/infra-base-pin --json number -q .number)
gh api "repos/{owner}/{repo}/issues/$n/comments" \
  --jq '.[] | select(.body | startswith("<!-- rendered-diff -->")) | .body' \
  | grep -E '<summary>|^No rendered'
```

```
No rendered change - this PR alters nothing any cluster receives.
```

The old `infrastructure` root is absent because no binding names it on either side any more, and the three overlays render as before. Then merge:

```sh
gh pr merge --merge --delete-branch \
&& git switch main \
&& git pull
```

**Why the order matters, and why these are two PRs where dev was one.** A binding move and a base edit in one commit look safe: the end state renders identically. The transition does not. A stamp reconciles the new commit under its *old* path before the binding that re-points it lands, because the binding is applied by a different stamp. For that one reconcile prod would render base as the commit left it, and a HelmRelease with no version means "the newest chart in the repository". One reconcile is enough for Helm to start an upgrade to whatever that is, on prod, with no rung below it. Retiring the pin in a PR of its own, after the pointer has moved, is [retire in two steps](../appendices/patterns.md#6-retire-in-two-steps): stop reading, then delete. It is also why the second PR's type is `refactor` where the first was `bind`: the [commit convention](../appendices/commit-convention.md) reserves `bind` for a change where nothing but the pointer moves, and a base edit reaches every class, so it is typed by what it touches, and stage 21's `base-gate` judges it as one.

Gate: the fleet on its overlays, still green, release revisions still unmoved:

```sh
for c in kind-ggp-local-01:platform kind-ggp-dev-01:dev kind-ggp-prod-01:prod; do
  ctx=${c%%:*}; class=${c#*:}
  kubectl --context $ctx -n flux-system get kustomization infrastructure \
    -o jsonpath="$ctx: {.spec.path} Ready={.status.conditions[?(@.type==\"Ready\")].status}{\"\n\"}"
done
for ctx in kind-ggp-local-01 kind-ggp-dev-01 kind-ggp-prod-01; do
  kubectl --context $ctx -n traefik get helmrelease traefik \
    -o jsonpath="$ctx: chart {.status.history[0].chartVersion} release revision {.status.history[0].version}{'\n'}"
done | diff - /tmp/infra-revisions-before.txt && echo "release revisions: unmoved on every cluster"
for c in kind-ggp-local-01:app-dev kind-ggp-dev-01:app-dev kind-ggp-prod-01:app-prod; do
  kubectl --context ${c%%:*} -n flux-system wait kustomization/${c#*:} --for=condition=Ready --timeout=2m
done
./scripts/checkpoint-07
```

Three `Ready=True` lines each naming its class overlay, then `release revisions: unmoved on every cluster`, three `condition met` lines, then the checkpoint green. The wait is there because the app stamps depend on `infrastructure` (stage 08) and report `DependencyNotReady` for one retry after it reconciles; a checkpoint run inside that window reads two app stamps as red for a reason that has nothing to do with this stage.

### 5. The first real bump, if the index is ahead

If the check at the top of the page found a newer chart, ride it now: platform first, and each rung below on the one above's evidence. This is the shape every Renovate PR will take from step 6 on, done once by hand so the robot's first PR meets rails you have already run. If the index was not ahead, skip to step 6.

```sh
new=$(curl -s https://traefik.github.io/charts/index.yaml | yq '.entries.traefik[0].version')
yq -i ".spec.chart.spec.version = \"$new\"" infrastructure/overlays/platform/patches/traefik.helmrelease.patch.yaml
git add infrastructure/overlays/platform
./scripts/pr-open pin/17/traefik-platform "pin(infrastructure): traefik chart $new, platform rung" <<EOF
## What is moving
The platform class overlay's traefik chart pin, to $new. Dev and prod stay where they are.

## Why now
The chart index is ahead of the fleet; the platform cluster absorbs the first look.

## Evidence
The rendered-diff comment: one root, one version line. Release revision to move by one on the platform cluster after merge.

## If it is wrong
Revert this merge; Helm rolls the platform release back to the previous chart.

Refs: #17
EOF
```

Read the comment stage 12 left: one root, `infrastructure/overlays/platform`, two lines, the version out and the version in. Then:

```sh
gh pr checks --watch --fail-fast \
&& gh pr merge --merge --delete-branch \
&& git switch main \
&& git pull
flux reconcile kustomization infrastructure --with-source --context kind-ggp-local-01
kubectl --context kind-ggp-local-01 -n traefik rollout status deploy/traefik --timeout=3m
kubectl --context kind-ggp-local-01 -n traefik get helmrelease traefik \
  -o jsonpath="kind-ggp-local-01: chart {.status.history[0].chartVersion} release revision {.status.history[0].version}{'\n'}"
```

Expected: the rollout completes, and the line shows the new chart and a release revision one higher than step 1 recorded. If instead the rollout waits and the new pod is `Pending` with `didn't have free ports`, the tree predates stage 05's `updateStrategy` values and the troubleshooting row says how the fix rides the ladder. That line is dev's evidence:

```sh
yq -i ".spec.chart.spec.version = \"$new\"" infrastructure/overlays/dev/patches/traefik.helmrelease.patch.yaml
git add infrastructure/overlays/dev
./scripts/pr-open pin/17/traefik-dev "pin(infrastructure): traefik chart $new, dev rung" <<EOF
## What is moving
The dev class overlay's traefik chart pin, to $new, the version the platform cluster now runs.

## Why now
The platform rung rolled out and its release revision moved by exactly one.

## Evidence
kind-ggp-local-01's helmrelease line after the platform merge; its traefik rollout complete.

## If it is wrong
Revert this merge; dev's release rolls back to the previous chart.

Refs: #17
EOF
gh pr checks --watch --fail-fast \
&& gh pr merge --merge --delete-branch \
&& git switch main \
&& git pull
flux reconcile kustomization infrastructure --with-source --context kind-ggp-dev-01
kubectl --context kind-ggp-dev-01 -n traefik rollout status deploy/traefik --timeout=3m
```

```sh
yq -i ".spec.chart.spec.version = \"$new\"" infrastructure/overlays/prod/patches/traefik.helmrelease.patch.yaml
git add infrastructure/overlays/prod
./scripts/pr-open pin/17/traefik-prod "pin(infrastructure): traefik chart $new, prod rung" <<EOF
## What is moving
The prod class overlay's traefik chart pin, to $new, the version platform and dev now run.

## Why now
Two rungs green on it; prod is last by design.

## Evidence
Both lower rungs' rollouts complete and their release revisions moved by one each.

## If it is wrong
Revert this merge; prod's release rolls back to the previous chart.

Refs: #17
EOF
gh pr checks --watch --fail-fast \
&& gh pr merge --merge --delete-branch \
&& git switch main \
&& git pull
flux reconcile kustomization infrastructure --with-source --context kind-ggp-prod-01
kubectl --context kind-ggp-prod-01 -n traefik rollout status deploy/traefik --timeout=3m
```

### 6. Hand the platform pin to Renovate

The HelmRelease comment has promised this since stage 05. Renovate's flux manager reads HelmRelease documents, resolves the chart's registry from the HelmRepository in the repo, and PRs version bumps, **scoped to the platform overlay only**, because the robot proposes at the top of the ladder and humans walk changes down it.

A robot's PR is still a PR, and stage 11's `pr-record` check judges it like yours: the title must obey the commit grammar and the body must cite an open work item, or the merge is refused. So the robot gets a standing work item first ([rule 2.5](../rules.md#25-every-change-has-a-work-item-the-trailer-is-the-reason) has no exception for robots; stage 14's robot gets one the same way), and the config makes every PR cite it and every title read `pin(infrastructure): …`:

```sh
gh label create automation --color 0e8a16 --description "standing work items for robots" --force
n=$(gh issue create --title "Platform currency: Renovate proposes chart bumps at the platform rung" --label automation \
  --body "Standing work item for Renovate (stage 13). Every PR it opens cites this issue; it closes when the robot is retired, not when a pin moves." \
  | grep -oE '[0-9]+$')
echo "Renovate's standing work item: #$n"
cat > renovate.json <<'EOF'
{
  "$schema": "https://docs.renovatebot.com/renovate-schema.json",
  "extends": [
    "config:recommended",
    ":semanticCommits",
    ":semanticCommitTypeAll(pin)",
    ":semanticCommitScope(infrastructure)"
  ],
  "enabledManagers": ["flux"],
  "flux": {
    "managerFilePatterns": [
      "/^infrastructure/base/.+\\.ya?ml$/",
      "/^infrastructure/overlays/platform/.+\\.ya?ml$/"
    ]
  },
  "ignorePaths": ["**/flux-system/**"],
  "prBodyNotes": ["Refs: #AUTOMATION_ISSUE"]
}
EOF
sed -i "s/#AUTOMATION_ISSUE/#$n/" renovate.json
git add renovate.json
./scripts/pr-open ci/17/renovate "ci(infrastructure): Renovate flux manager, platform overlay is the only update site" <<EOF
## What is moving
renovate.json: the flux manager, fenced to infrastructure/base (registry resolution) and overlays/platform (the only update site); titles as pin(infrastructure); every PR body citing #$n.

## Why now
Platform currency should enter the ladder by robot, at the rung nobody misses, through the same checks a human's PR meets.

## Evidence
managerFilePatterns names two paths; dev and prod overlays are outside both, and ignorePaths keeps the bootstrap manifests out. The standing work item is #$n, open.

## If it is wrong
Revert this merge; Renovate opens nothing.

Refs: #17
EOF
```

Read it; when the diff is what the body claims:

```sh
gh pr checks --watch --fail-fast \
&& gh pr merge --merge --delete-branch \
&& git switch main \
&& git pull
```

**Now install the robot.** The config is on `main`; nothing reads it until the app is on the repo, and that is a browser step, not a command:

1. Open <https://github.com/apps/renovate> and choose **Install** (or **Configure**, if the app is already on your account).
2. Pick the account that owns the config repo, then **Only select repositories** and select the config repo alone. The app needs no other repository, and the leak posture below says why that matters.
3. GitHub hands you to Mend's onboarding. Product: **Renovate Only** (the other needs a Mend licence). Mode: **Scan and Alert**, not the default **Scan Only**, which sets Renovate to silent: no dashboard issue, no PRs, and a stage that waits forever. Confirm.
4. The developer portal (<https://developer.mend.io>, signed in with GitHub) then lists the repo with Renovate **Enabled**, mode **Interactive**, and **Last Job Run** empty until the first job runs. Click the repository name to watch jobs arrive, or to trigger one if the page offers it; the first is scheduled within a few minutes of enabling.

Gate: the Dependency Dashboard is the first artefact, and it is nothing more than an issue in this repo, titled "Dependency Dashboard", whose body Renovate rewrites on every job: the PRs it has open, with a rebase checkbox each, the files and versions it detects, and a checkbox to run again. There is no page elsewhere. A bump PR follows only if the chart index is ahead of the platform overlay's pin. Wait for the issue, then list the robot's PRs:

```sh
for i in $(seq 1 40); do
  n=$(gh issue list --search "Dependency Dashboard in:title" --json number -q '.[0].number')
  [ -n "$n" ] && { echo "Dependency Dashboard: #$n"; break; }
  sleep 15
done
gh pr list --author app/renovate --state open --json number,title -q '.[] | "#\(.number)  \(.title)"'
```

```
Dependency Dashboard: #<n>
```

The open-PR list is empty after step 5, because the index is not ahead; the first bump PR arrives when Traefik next releases. (`--state open` on purpose: a PR the robot closed itself is still a PR, and `--state all` would list it for ever.) An empty dashboard is a current fleet: its "Detected Dependencies" section lists the two Traefik files the fence admits and nothing under "Open". To make the robot run again at any time, tick the checkbox at the bottom of that issue ("trigger a request for Renovate to run again"); a change to `renovate.json` on `main` also starts a job. When it does, it targets exactly one file, the platform overlay's patch, titled `pin(infrastructure): …`, its body ending `Refs: #<n>`, its `pr-record` check green and its rendered-diff comment naming one root. If ten minutes pass with no issue, either the app is not on this repository (step 2 above, and the installation's repository list) or the mode is Scan Only (the portal's settings, per repository or for the account; switch it to Scan and Alert and the next job opens the issue).

Why the config is shaped that way: `managerFilePatterns` (the option that replaced `fileMatch`) takes regexes between slashes and is additive to the manager's defaults, and the flux manager's one default is `gotk-components.yaml` anywhere, the bootstrap manifests under every cluster's `flux-system/`, where the version is Flux's own. That version follows the AKS extension ([rule 4.3](../rules.md#43-the-version-policy-follow-the-authority-at-the-pace-kubernetes-sets)) and climbs at [stage 16](stage-16.md), never by robot, so `ignorePaths` takes the whole `flux-system/` tree out of the robot's sight; a negated pattern inside the fence does not do this (it widens the match to every file), and `ignorePaths` replaces the recommended preset's list, which names folders this repo does not have. So the fence is those two trees: the platform overlay, where the only version the robot may move lives, and base, which it must read to find the HelmRepository that names the chart's registry, and where there is no version left to bump once step 4's last rung retires it (if one ever returns there, the robot's `pin` on a base path is exactly what stage 21's `base-gate` refuses); the three `:semantic…` presets make the title `pin(infrastructure): update helm release traefik to v…`, which the commit grammar accepts; and `prBodyNotes` puts the `Refs:` line in every PR body, which `issue-gate` reads. The config is committed before the app is installed, so Renovate skips its onboarding PR (that PR exists only for a repo with no config on its default branch) and its first artefact is the Dependency Dashboard issue that `config:recommended` enables.

**Why Renovate and not Dependabot?** Dependabot is built into GitHub and free, and it is the right tool where its ecosystems reach: the app repo's Dockerfile, and Actions pins in both repos (including SHA-pinned actions). But none of its ecosystems read what this repo actually holds: no Flux manager, no Helm-chart pins inside a `HelmRelease`, no kustomize `images:` pins, no custom managers for a file like `clusters/versions.yaml`. Renovate has all four, and the flux manager above is the whole point of this step. Run both if you like; they never meet, because they cannot see the same files.

**And name the trade you are making.** The hosted Renovate app means a third party reads this private repo: weigh that against the [leak posture](../appendices/repo-leak-posture.md) you adopted at stage 06, and note the posture is what makes it survivable (the repo grants nothing by being read). The escape hatch is self-hosting: Renovate runs fine as a scheduled workflow or container with a token of your choosing, the `renovate.json` above unchanged. You trade the third party for custody of one more credential, which is Act V's subject.

**Standing instruction from here on:** a Renovate PR *is* the next rehearsal. Read its rendered diff, merge it (platform), watch the rollout, then copy the pin to dev and prod by PR, on evidence, exactly as step 5 did. Note what the ruleset does with a robot's PR: nothing special. Renovate opens PRs as a GitHub App, they carry the same required checks, and a human merges them. The robot got exactly the *proposal* privilege, and stage 14's robot gets exactly the *dev* one.

## What this rehearsed, beyond Traefik

A controller *swap* rides identical rails: the replacement lands in `base/` beside the incumbent, the platform overlay selects it, traffic proof, then rung by rung, then the incumbent's files delete. The whole swap is a sequence of reviewed diffs with per-cluster verdicts. Reality has already demonstrated the need once (stage 05's ingress-nginx retirement story), and Act VIII's Ingress→Gateway API migration will be this stage's mechanics at full scale.

## Stop & measure

- [ ] Every cluster is bound to its class overlay and green, and the checkpoint agrees:

```sh
for c in kind-ggp-local-01:platform kind-ggp-dev-01:dev kind-ggp-prod-01:prod; do
  ctx=${c%%:*}; class=${c#*:}
  kubectl --context $ctx -n flux-system get kustomization infrastructure \
    -o jsonpath="$ctx: {.spec.path} Ready={.status.conditions[?(@.type==\"Ready\")].status}{\"\n\"}"
done
./scripts/checkpoint-07
```

Expected: three lines, `./infrastructure/overlays/<class> Ready=True` each, then the checkpoint's PASS lines.

- [ ] The release revisions tell the story: unmoved by the restructure, one higher per cluster if step 5 ran:

```sh
for ctx in kind-ggp-local-01 kind-ggp-dev-01 kind-ggp-prod-01; do
  kubectl --context $ctx -n traefik get helmrelease traefik \
    -o jsonpath="$ctx: chart {.status.history[0].chartVersion} release revision {.status.history[0].version}{'\n'}"
done
cat /tmp/infra-revisions-before.txt
```

- [ ] The stage's PRs, in ladder order, and the robot's standing work item open:

```sh
gh pr list --state merged --search '"Refs: #17" in:body' --json number,title -q '.[] | "#\(.number)  \(.title)"'
gh issue list --label automation --json number,title,state -q '.[] | "#\(.number)  \(.state)  \(.title)"'
```

Expected: six titles without step 5 (`refactor`, `bind`, `bind`, `bind`, `refactor`, `ci`), nine with it (three `pin(infrastructure)` between), and the Renovate issue `OPEN`.

- [ ] Renovate is installed and reading the repo:

```sh
gh issue list --search "Dependency Dashboard in:title" --json number,title -q '.[] | "#\(.number)  \(.title)"'
gh pr list --author app/renovate --state open --json number,title -q '.[] | "#\(.number)  \(.title)"'
```

Expected: the dashboard issue; no open Renovate PR if the fleet is current, else one `pin(infrastructure): …` PR with a green `pr-record` check.

Tag the boundary ([using the course §5](../using-the-course.md#5-tags-at-every-boundary)):

```sh
git tag stage-13 \
&& git push origin stage-13 \
&& gh issue close 17 --comment "stage-13 tagged"
```

## Troubleshooting

| Symptom | Likely cause | Fix |
|---|---|---|
| `kubectl` refuses every context after a reboot | Under podman the kind node containers stay stopped (`Exited (137)`); state survives inside them | `podman start ggp-local-01-control-plane ggp-dev-01-control-plane ggp-prod-01-control-plane`, wait a minute, `flux check --context kind-ggp-local-01` |
| Step 2's parity gate fails | The patch's version differs from base's, or the patch's `metadata` does not match the HelmRelease (name `traefik`, namespace `traefik`) | Step 2 reads the version off base into `$v`; both must agree until step 4's final rung retires the base pin |
| `flux reconcile` on a rung waits out its timeout, and the HelmRelease history shows a failed release at a newer chart between two at the pin | The base pin was retired in the same commit that re-pointed the binding; the stamp reconciled that commit under its old path once, rendered base with no version, and Helm read no version as "latest" | Two PRs, the pointer then the pin (step 4); the fleet is healthy once the binding lands, and the history keeps the failed revision as the record |
| `checkpoint-07` reports an `app-*` stamp not Ready right after a rung merges, and it is green a minute later | The dependency cascade: the app stamps depend on `infrastructure` and report `DependencyNotReady` for one retry after it reconciles | Nothing; the wait before the checkpoint in step 4 exists for this, and `flux events --for Kustomization/app-prod` shows the retry |
| The bump's rollout never completes: the HelmRelease stalls `UpgradeFailed … timeout waiting for Deployment`, and the new pod is `Pending` with `FailedScheduling: didn't have free ports` | The chart's default rollout surges a second pod, and Traefik's host ports 80 and 443 are held by the first; on one node the second can never bind them. Stage 05 sets `updateStrategy` (`maxSurge: 0`, `maxUnavailable: 1`) for this; a tree built before it lacks the values | Base is sacred, so the values ride the ladder: a `fix(infrastructure)` PR adding `spec.values.updateStrategy` to the platform overlay's patch (a new generation retries the stalled upgrade, and replacement lets it schedule), the same on dev before its pin and on prod before its pin, then one `refactor` PR that moves the values into base and drops them from the patches, whose comment reads "No rendered change" |
| Renovate's first PR is `pin(infrastructure): update dependency fluxcd/flux2 …`, touching every cluster's `flux-system/gotk-components.yaml` | `ignorePaths` is missing, so the flux manager's default pattern reached the bootstrap manifests; Flux's version is not the robot's to move | Close the PR unmerged. Add `"ignorePaths": ["**/flux-system/**"]` to `renovate.json` by PR, then run a job from the portal; the dashboard's detected dependencies shrink to the two Traefik files and the robot closes its own PR as no longer needed |
| Old-path cluster goes red after the restructure merges | The explicit root `infrastructure/kustomization.yaml` is missing; the controller guessed at the tree and swallowed the overlays' patch files | Step 2's `kustomize create --resources base/traefik` at the infrastructure root |
| Helm release revision bumped on a "render-identical" rung | The render was not identical; re-run the step-2 diff gate against that overlay | The gate exists to run *before* the PR, not after |
| `pr-record` red on a Renovate PR | The title is not `pin(infrastructure): …` or the body has no `Refs:` line: the `:semantic…` presets or `prBodyNotes` are missing from `renovate.json`, or the standing issue closed | Step 6's config; reopen the issue if it was closed by hand |
| Renovate PR edits dev/prod overlays too | `managerFilePatterns` widened, or the bump was made in `base/` | Only `base/` (registry resolution) and `overlays/platform/` (the update site) are matched; dev/prod pins move by human PR |
| Renovate opens no PR at all | Pin already at the index's newest (step 5 left it there), or the app lacks repo access | The two-line check at the top of the page tells you which; the dashboard issue proves the app reads the repo |

## What you learned

The platform got what the app has had since stage 07: a pin per class, promotion as a reviewed diff, evidence per rung, proven on a render-identical change before any real one rides it. And the robot enters at exactly one point: the top of the ladder, where the cluster nobody misses absorbs the risk, through the same checks a human meets. Stage 12's comment on every one of those PRs is the blast radius the reviewer reads, Renovate's included.

---

**Next:** [14 - Image automation (the robot on the dev rung)](stage-14.md)
